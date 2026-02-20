use std::error::Error;
use std::io::{Read, Write};
use std::path::PathBuf;

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

fn main() -> Result<(), Box<dyn Error>> {
    // We don't take locks on stdout, so we shall not use it outside of this event loop
    let mut watcher = notify::recommended_watcher(|event: notify::Result<notify::Event>| {
        use notify::{
            EventKind,
            event::{AccessKind, AccessMode, ModifyKind},
        };

        let mut stdout = std::io::stdout();

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

                let serialized = serde_json::ser::to_string(&response).unwrap();
                let len = serialized.len() as u32;

                stdout.write(&len.to_ne_bytes()).unwrap();
                stdout.write(serialized.as_bytes()).unwrap();

                let _ = stdout.flush();
            }
            _ => (),
        }
    })?;

    let mut stdin = std::io::stdin();

    loop {
        let len = {
            let mut buf = [0u8; 4];
            stdin.read_exact(&mut buf)?;

            u32::from_ne_bytes(buf) as usize
        };

        let message: NotifyServerMessage = {
            let mut buf = vec![0u8; len];
            stdin.read_exact(&mut buf)?;

            serde_json::de::from_slice(&buf)?
        };

        match message.command {
            NotifyServerCommand::Add => {
                let _ = watcher.watch(&message.file, RecursiveMode::NonRecursive);
            }
            NotifyServerCommand::Remove => {
                let _ = watcher.unwatch(&message.file);
            }
        }
    }
}
