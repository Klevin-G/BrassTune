import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';

const assetsDirectory = new URL('../dist/assets/', import.meta.url);
const assetNames = await readdir(assetsDirectory);
const expectedLocales = ['es', 'zh-Hans', 'zh-Hant', 'ar', 'fr', 'de', 'ru', 'pt-BR', 'ja', 'ko', 'vi'];
const missing = expectedLocales.filter((locale) => !assetNames.some((name) => name.startsWith(`locale-${locale}-`) && name.endsWith('.js')));
if (missing.length > 0) throw new Error(`Missing lazy locale chunks: ${missing.join(', ')}`);

const indexHtml = await readFile(new URL('../dist/index.html', import.meta.url), 'utf8');
const entryName = indexHtml.match(/<script[^>]+src="\/assets\/(index-[^"]+\.js)"/)?.[1];
if (!entryName) throw new Error('Could not identify the production entry chunk.');
const entrySource = await readFile(join(assetsDirectory.pathname, entryName), 'utf8');
if (entrySource.includes('Псевдолокаль') || entrySource.includes('調音器與練習')) {
  throw new Error('A production translation leaked into the eager entry chunk.');
}

console.log(`Verified ${expectedLocales.length} lazy locale chunks outside ${entryName}.`);
