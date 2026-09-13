import { readFile } from 'node:fs/promises';

// njs deliberately removes the global Function constructor. Gleam's equality
// helper already rejects non-objects before this check, so Function is redundant.
// Adapt only the build input; retain njs's runtime restrictions and never modify
// Gleam's generated artifacts in place.
export const gleamRuntimeCompatibility = {
    name: 'gleam-njs-runtime',
    setup(build) {
        build.onLoad({ filter: /[/\\]prelude\.mjs$/ }, async ({ path }) => ({
            contents: (await readFile(path, 'utf8')).replace(
                '[Promise, WeakSet, WeakMap, Function]',
                '[Promise, WeakSet, WeakMap]',
            ),
            loader: 'js',
        }));
    },
};
