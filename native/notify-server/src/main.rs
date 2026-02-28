#![feature(btree_cursors)]
#![feature(path_is_empty)]

use std::borrow::Cow;
use std::collections::{BTreeSet, HashMap};
use std::ops::Bound;

use std::fmt::Debug;
use std::io::{Read, Write};

use std::path::{Path, PathBuf};

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, mpsc};

use std::error::Error;
use std::thread;
use thiserror::Error;

use notify::{Config, EventKindMask, RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};

mod windows;

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

// Toggle whether update events are sent when files are removed. Update
// events are always sent for removals inside watched directories.
static RELOAD_REMOVED: AtomicBool = AtomicBool::new(false);

enum WatchRequest {
    Watch(PathBuf),
    Unwatch(PathBuf),
}

fn main() -> Result<(), Box<dyn Error>> {
    #[cfg(target_os = "windows")]
    {
        windows::set_fd_mode(0, windows::mode::_O_BINARY).unwrap();
        windows::set_fd_mode(1, windows::mode::_O_BINARY).unwrap();
        windows::set_fd_mode(2, windows::mode::_O_BINARY).unwrap();
    }

    type DirectoryMap<'a> = Arc<Mutex<HashMap<PathBuf, BTreeSet<Cow<'a, Path>>>>>;

    // Maps a directory which is actually being watched to children inside it
    // which we have received requests to watch.
    //
    // We do this so that we can receive events when a file is removed and
    // then another file is renamed over it, or when registering watches
    // for files that don't exist.
    //
    // The child doesn't have to be a direct child, that way there can be
    // multiple levels of "non-existence" that can be steadily filled in.
    //
    // NOTE: "" is a valid entry; it is used to indicate that the directory
    // itself is being watched.
    let dir_watched_children: DirectoryMap<'_> = Arc::new(Mutex::new(HashMap::new()));

    let (tx, rx) = mpsc::channel::<WatchRequest>();

    let mut watcher = {
        let tx = tx.clone();
        let dir_watched_children = dir_watched_children.clone();

        RecommendedWatcher::new(
            move |event: notify::Result<notify::Event>| {
                use notify::{Event, EventKind, event::*};

                fn handle_event(
                    tx: mpsc::Sender<WatchRequest>,
                    event: notify::Event,
                    dir_watched_children: DirectoryMap<'_>,
                    reload_removed: bool,
                ) {
                    match event {
                        Event {
                            kind: EventKind::Create(kind),
                            paths,
                            ..
                        } => {
                            let path = paths.into_iter().next().unwrap();
                            let mut map = dir_watched_children.lock().unwrap();

                            // NOTE: the cases below are not mutually exclusive!

                            // We received an update event for a directory and it is being watched
                            if let Some(children) = map.get(&path)
                                && children.contains(Path::new(""))
                            {
                                let _ = ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                    file: &path,
                                });
                            }

                            if let Some(parent) = path.parent()
                                && let Some(children) = map.get_mut(parent)
                            {
                                let dot_in_children = children.contains(Path::new(""));

                                if let Some(file) = path.file_name() {
                                    let mut cursor =
                                        children.lower_bound_mut(Bound::Included(Path::new(file)));
                                    let child = cursor.next();

                                    if child.is_some_and(|x| x == Path::new(file)) {
                                        let _ =
                                            ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                                file: &path,
                                            });
                                    }

                                    // We received an update event for a child,
                                    // but the directory is being watched
                                    if dot_in_children {
                                        let _ =
                                            ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                                file: parent,
                                            });
                                    }

                                    // The map manipulation to separate children only makes
                                    // sense if the child that was created is a directory
                                    if kind == CreateKind::Folder
                                        || (kind == CreateKind::Any && path.is_dir())
                                    {
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
                                            tx.send(WatchRequest::Watch(path.clone()));
                                            map.insert(path, set);
                                        }
                                    }
                                }
                            }
                        }
                        Event {
                            kind: EventKind::Remove(kind),
                            paths,
                            ..
                        } => {
                            let mut path = paths.into_iter().next().unwrap();
                            let mut map = dir_watched_children.lock().unwrap();

                            if let Some(parent) = path.parent()
                                && let Some(children) = map.get_mut(parent)
                            {
                                // If the parent of the file/directory being removed is being watched,
                                // we have to send an update event to it
                                if children.contains(Path::new("")) {
                                    let _ = ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                        file: parent,
                                    });
                                }

                                // If the file being removed is being watched and the user chose to
                                // receive update events for removed files, send an update event
                                if reload_removed
                                    && let Some(file) = path.file_name()
                                    && children.contains(Path::new(&file))
                                {
                                    let _ = ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                        file: &path,
                                    });
                                }
                            }

                            // If this directory has any watches and it is getting
                            // removed, we have to start watching its parent and reparent
                            // any children
                            //
                            // WARN: I don't think I need to unwatch here /shrug
                            //
                            // NOTE: modifies `path` so it should come in last
                            if let Some(parent) = path.parent()
                                && let Some(file) = path.file_name().map(|x| Path::new(x))
                                && let Some(children) = map.remove(&path)
                            {
                                let set: BTreeSet<_> = children
                                    .into_iter()
                                    .map(|x| Cow::Owned(file.join(x)))
                                    .collect();

                                if let Some(existing) = map.get_mut(parent) {
                                    existing.extend(set);
                                } else {
                                    path.pop();

                                    tx.send(WatchRequest::Watch(path.clone()));
                                    map.insert(path, set);
                                }
                            }
                        }
                        Event {
                            kind: EventKind::Modify(ModifyKind::Data(..)),
                            paths,
                            ..
                        } => {
                            let path = paths.into_iter().next().unwrap();
                            let map = dir_watched_children.lock().unwrap();

                            if let Some(parent) = path.parent()
                                && let Some(children) = map.get(parent)
                                && let Some(file) = path.file_name()
                            {
                                if children.contains(Path::new(&file)) {
                                    let _ = ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                        file: &path,
                                    });
                                }

                                // if children.contains(Path::new("")) {
                                //     let _ = ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                //         file: parent,
                                //     });
                                // }
                            }
                        }
                        Event {
                            kind: EventKind::Modify(ModifyKind::Metadata(..)),
                            paths,
                            ..
                        } => {
                            let path = paths.into_iter().next().unwrap();
                            let map = dir_watched_children.lock().unwrap();

                            if let Some(parent) = path.parent()
                                && let Some(children) = map.get(parent)
                                && children.contains(Path::new(""))
                            {
                                let _ = ser_json_len_prefixed_stdout(&NotifyEvent::Update {
                                    file: parent,
                                });
                            }
                        }
                        Event {
                            kind: EventKind::Modify(ModifyKind::Name(kind)),
                            paths,
                            ..
                        } => {
                            match kind {
                                RenameMode::From => handle_event(
                                    tx,
                                    Event {
                                        kind: EventKind::Remove(RemoveKind::Any),
                                        paths,
                                        attrs: EventAttributes::new(),
                                    },
                                    dir_watched_children,
                                    reload_removed,
                                ),
                                RenameMode::To => handle_event(
                                    tx,
                                    Event {
                                        kind: EventKind::Create(CreateKind::Any),
                                        paths,
                                        attrs: EventAttributes::new(),
                                    },
                                    dir_watched_children,
                                    reload_removed,
                                ),
                                // Naive way to deal with it
                                RenameMode::Both => {
                                    let mut iter = paths.into_iter();

                                    let from = iter.next().unwrap();
                                    let to = iter.next().unwrap();

                                    handle_event(
                                        tx.clone(),
                                        Event {
                                            kind: EventKind::Remove(RemoveKind::Any),
                                            paths: vec![from],
                                            attrs: EventAttributes::new(),
                                        },
                                        dir_watched_children.clone(),
                                        reload_removed,
                                    );

                                    handle_event(
                                        tx,
                                        Event {
                                            kind: EventKind::Create(CreateKind::Any),
                                            paths: vec![to],
                                            attrs: EventAttributes::new(),
                                        },
                                        dir_watched_children,
                                        reload_removed,
                                    );
                                }
                                _ => (),
                            }
                        }
                        Event {
                            kind:
                                EventKind::Access(..)
                                | EventKind::Any
                                | EventKind::Other
                                | EventKind::Modify(ModifyKind::Any | ModifyKind::Other),
                            ..
                        } => (),
                    }
                }

                if let Ok(event) = event {
                    handle_event(
                        tx.clone(),
                        event,
                        dir_watched_children.clone(),
                        RELOAD_REMOVED.load(Ordering::Relaxed),
                    );
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

    thread::spawn(move || {
        while let Ok(request) = rx.recv() {
            match request {
                WatchRequest::Watch(path) => {
                    watcher.watch(&path, RecursiveMode::NonRecursive);
                }
                WatchRequest::Unwatch(path) => {
                    watcher.watch(&path, RecursiveMode::NonRecursive);
                }
            }
        }
    });

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
                    tx.send(WatchRequest::Watch(file.clone()));

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

                    tx.send(WatchRequest::Watch(base.into()));

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

                if let Some(children) = map.get_mut(&file)
                    && children.contains(Path::new("").into())
                {
                    children.remove(Path::new("").into());

                    if children.is_empty() {
                        map.remove(&file);
                        tx.send(WatchRequest::Unwatch(file));
                    }
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
                            tx.send(WatchRequest::Unwatch(ancestor.into()));
                            map.remove(ancestor);

                            break;
                        }
                    }
                }
            }
            NotifyMessage::Reconfigure { reload_removed } => {
                if let Some(value) = reload_removed {
                    RELOAD_REMOVED.swap(value, Ordering::Relaxed);
                }
            }
        }
    }
}
