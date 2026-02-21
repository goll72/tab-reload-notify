use std::collections::{BTreeSet, HashMap};

use std::io::{Read, Write};
use std::path::PathBuf;

use std::sync::Mutex;

use std::error::Error;
use thiserror::Error;

use notify::{RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum NotifyServerCommand {
    Add,
    Remove,
}

#[derive(Deserialize)]
struct NotifyServerMessage {
    command: NotifyServerCommand,
    file: PathBuf,
}

#[derive(Serialize)]
#[serde(rename_all = "lowercase")]
enum NotifyServerEventType {
    Update,
    Error,
}

#[derive(Serialize)]
struct NotifyServerEvent {
    r#type: NotifyServerEventType,
    file: PathBuf,
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
    // NOTE: "." is a valid entry if the directory itself is being watched,
    // but it is not supposed to ever be the only entry.
    let dir_watched_children: Mutex<HashMap<PathBuf, BTreeSet<PathBuf>>> =
        Mutex::new(HashMap::new());

    let mut watcher = notify::recommended_watcher(|event: notify::Result<notify::Event>| {
        use notify::{
            EventKind,
            event::{AccessKind, AccessMode, ModifyKind},
        };

        match event {
            Ok(event) => {
                if !matches!(
                    event.kind,
                    EventKind::Create(..)
                        | EventKind::Modify(ModifyKind::Data(..))
                        | EventKind::Access(AccessKind::Close(AccessMode::Any | AccessMode::Write))
                ) {
                    return;
                }

                let response = NotifyServerEvent {
                    r#type: NotifyServerEventType::Update,
                    file: event.paths[0].clone(),
                };

                let _ = ser_json_len_prefixed_stdout(&response);
            }
            _ => (),
        }
    })?;

    loop {
        let message: NotifyServerMessage = de_json_len_prefixed_stdin()?;

        match message.command {
            NotifyServerCommand::Add => {
                // NOTE: this is racy, but there is not much we can do at this point
                if !message.file.exists() {
                    let response = NotifyServerEvent {
                        r#type: NotifyServerEventType::Error,
                        file: message.file,
                    };

                    ser_json_len_prefixed_stdout(&response)?;
                    continue;
                }

                if message.file.is_dir() {
                    let _ = watcher.watch(&message.file, RecursiveMode::NonRecursive);
                } else {
                    // TODO: watch first parent directory that exists as we traverse
                    // up the directory tree and put it on dir_watched_children
                }
            }
            NotifyServerCommand::Remove => {
                let _ = watcher.unwatch(&message.file);
            }
        }
    }
}
