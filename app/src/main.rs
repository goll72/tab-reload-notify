#![feature(btree_cursors)]
#![feature(path_is_empty)]
#![feature(path_trailing_sep)]

use std::borrow::Cow;
use std::collections::{BTreeSet, HashMap};
use std::ops::Bound;

use std::fmt::Debug;
use std::io::{Read, Write};

use std::path::{Path, PathBuf};

use std::sync::{Arc, Mutex};

use std::error::Error;
use thiserror::Error;

use notify::{Config, EventKindMask, RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
#[serde(tag = "command")]
enum NotifyMessage {
    Add { file: PathBuf },
    Remove { file: PathBuf },
    Reconfigure { reload_removed: Option<bool> },
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
#[serde(tag = "type")]
enum NotifyEvent<'a> {
    Update { file: &'a Path },
    Error { file: &'a Path },
}

#[derive(Error, Debug)]
enum JsonIoError {
    #[error("Couldn't serialize/deserialize data")]
    Serde(#[from] serde_json::Error),
    #[error("I/O error")]
    Io(#[from] std::io::Error),
}

fn ser_json_len_prefixed_stdout<T: Serialize>(x: &T) -> Result<(), JsonIoError> {
    let serialized = serde_json::ser::to_string(x)?;
    let len = serialized.len() as u32;

    let mut stdout = std::io::stdout().lock();

    stdout.write(&len.to_ne_bytes())?;
    stdout.write(serialized.as_bytes())?;

    stdout.flush()?;

    Ok(())
}

fn de_json_len_prefixed_stdin<T: for<'a> Deserialize<'a>>() -> Result<T, JsonIoError> {
    let mut stdin = std::io::stdin();

    let len = {
        let mut buf = [0u8; 4];
        stdin.read_exact(&mut buf)?;

        u32::from_ne_bytes(buf) as usize
    };

    let mut buf = vec![0u8; len];
    stdin.read_exact(&mut buf)?;

    Ok(serde_json::de::from_slice(&buf)?)
}

fn main() -> Result<(), Box<dyn Error>> {
    // Maps a directory to children inside it that are actually being watched.
    //
    // We do this so that we can receive events when a file is removed and
    // then another file is renamed over it, or when registering watches
    // for files that don't exist.
    //
    // The child doesn't have to be a direct child, that way there can be
    // multiple levels of "non-existence" that can be steadily filled in.
    //
    // NOTE: "" is a valid entry, that is used to indicate that the directory
    // itself is being watched.
    let dir_watched_children: Arc<Mutex<HashMap<PathBuf, BTreeSet<Cow<'_, Path>>>>> =
        Arc::new(Mutex::new(HashMap::new()));

    let mut watcher = {
        let dir_watched_children = dir_watched_children.clone();

        RecommendedWatcher::new(
            move |event: notify::Result<notify::Event>| {
                use notify::{Event, EventKind, event::*};

                match event {
                    Ok(Event {
                        kind: EventKind::Create(kind),
                        paths,
                        ..
                    }) => {
                        let mut path = paths.into_iter().next().unwrap();
                        let mut map = dir_watched_children.lock().unwrap();

                        // NOTE: the cases below are not mutually exclusive!

                        // We received an update event for a directory and it is being watched
                        if let Some(children) = map.get(&path)
                            && children.contains(Path::new(""))
                        {
                            let _ =
                                ser_json_len_prefixed_stdout(&NotifyEvent::Update { file: &path });
                        }

                        if let Some(parent) = path.parent()
                            && let Some(children) = map.get_mut(parent)
                        {
                            let dot_in_children = children.contains(Path::new("").into());

                            // We received an update event for a child, which
                            // is being watched or has children being watched
                            if let Some(file) = path.file_name() {
                                let mut cursor =
                                    children.lower_bound_mut(Bound::Included(Path::new(file)));
                                let child = cursor.next();

                                if child.is_some_and(|x| x == Path::new(file)) {
                                    let _ = ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                        file: &path,
                                    });
                                }

                                // The map manipulation to separate children only makes
                                // sense if the child that was created is a directory
                                if kind == CreateKind::Folder {
                                    let mut set = BTreeSet::new();

                                    while let Some(child) = cursor.peek_next()
                                        && child.starts_with(file)
                                    {
                                        let child = cursor.remove_next().unwrap();

                                        set.insert(
                                            child.strip_prefix(file).unwrap().to_owned().into(),
                                        );
                                    }

                                    if let Some(existing) = map.get_mut(&path) {
                                        existing.extend(set);
                                    } else {
                                        map.insert(path.clone(), set);
                                    }
                                }
                            }

                            // We received an update event for a child,
                            // but the directory is being watched
                            //
                            // NOTE: this has to come in last, since it modifies `path`
                            if dot_in_children {
                                path.pop();

                                let _ = ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                    file: &path,
                                });
                            }
                        }
                    }
                    Ok(Event {
                        kind: EventKind::Remove(..),
                        paths,
                        ..
                    }) => {
                        let mut path = paths.into_iter().next().unwrap();
                        let mut map = dir_watched_children.lock().unwrap();

                        if let Some(parent) = path.parent()
                            && let Some(children) = map.get_mut(parent)
                        {
                            let dot_in_children = children.contains(Path::new("").into());

                            // NOTE: this has to come in last, since it modifies `path`
                            if dot_in_children {
                                path.pop();

                                let _ = ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                    file: &path,
                                });
                            }
                        }
                    }
                    Ok(Event {
                        kind: EventKind::Modify(ModifyKind::Data(..)),
                        paths,
                        ..
                    }) => {
                        let mut path = paths.into_iter().next().unwrap();
                        let mut map = dir_watched_children.lock().unwrap();
                    }
                    Ok(Event {
                        kind: EventKind::Modify(ModifyKind::Metadata(..)),
                        paths,
                        ..
                    }) => {}
                    Ok(Event {
                        kind: EventKind::Modify(ModifyKind::Name(..)),
                        paths,
                        ..
                    }) => {}
                    _ => (),
                }
            },
            Config::default().with_event_kinds(
                EventKindMask::CREATE
                    | EventKindMask::REMOVE
                    | EventKindMask::MODIFY_DATA
                    | EventKindMask::MODIFY_META
                    | EventKindMask::MODIFY_NAME,
            ),
        )?
    };

    loop {
        match de_json_len_prefixed_stdin()? {
            NotifyMessage::Add { file } => {
                // Relative paths are not supported
                if file.is_relative() {
                    ser_json_len_prefixed_stdout(&NotifyEvent::Error { file: &file })?;

                    continue;
                }

                // Path exists and is a directory
                if file.is_dir() {
                    let _ = watcher.watch(&file, RecursiveMode::NonRecursive);

                    dir_watched_children
                        .lock()
                        .unwrap()
                        .entry(file)
                        .or_default()
                        .insert(Path::new("").into());
                } else {
                    // This error condition can only happen if file is `/`,
                    // which is presumed to be a world-readable directory.
                    //
                    // XXX: *nix-centric error handling?
                    let parent = file
                        .parent()
                        .ok_or("File which isn't a directory without parent path, perhaps there is no read permission for `/'?")?;

                    let base = parent.ancestors().find(|x| x.is_dir()).ok_or(
                        "Couldn't find an existing parent for file when traversing upward",
                    )?;

                    let rest = file.strip_prefix(base)?.to_owned();

                    let _ = watcher.watch(&base, RecursiveMode::NonRecursive);

                    dir_watched_children
                        .lock()
                        .unwrap()
                        .entry(base.into())
                        .or_default()
                        .insert(rest.into());
                }
            }
            NotifyMessage::Remove { file } => {
                let mut map = dir_watched_children.lock().unwrap();

                if let Some(children) = map.get(&file)
                    && children.contains(Path::new("").into())
                {
                    let _ = watcher.unwatch(&file);
                } else if let Some(parent) = file.parent() {
                    for ancestor in parent.ancestors() {
                        let Some(children) = map.get_mut(ancestor) else {
                            continue;
                        };

                        let Ok(suffix) = file.strip_prefix(ancestor) else {
                            continue;
                        };

                        children.remove(suffix);

                        if children.is_empty() {
                            let _ = watcher.unwatch(ancestor);
                            map.remove(ancestor);

                            break;
                        }
                    }
                }
            }
            NotifyMessage::Reconfigure { reload_removed } => todo!(),
        }
    }
}
