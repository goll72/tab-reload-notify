import path from "node:path";
import fs from "node:fs/promises";

export type File = {
    tag: "file";
    name: string;
};

export type Dir = {
    tag: "dir";
    name: string;
    children: FileHierarchy[];
};

export type FileHierarchy = File | Dir;

export const file = (name: string): File => ({ tag: "file", name });
export const dir = (name: string, children?: FileHierarchy[]): Dir => ({
    tag: "dir",
    name,
    children: children ?? [],
});

export const makeHierarchy = async (base: string, node: FileHierarchy) => {
    switch (node.tag) {
        case "dir": {
            const joined = path.join(base, node.name);

            await fs.mkdir(joined);
            await Promise.all(node.children.map(x => makeHierarchy(joined, x)));

            break;
        }
        case "file":
            await fs.writeFile(path.join(base, node.name), "");

            break;
    }
};
