// Synced from https://github.com/curiosus-dev/dotnet-tools, do not edit in place.
// Assembles .generated/docs from the repository docs/, the README files and the pages listed in docs.json.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { cp, glob, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const posix = path.posix;

export function parseRepository(value) {
    const match = /^(?:(?:git@|https:\/\/)github\.com[:/])?([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/.exec(value.trim());
    if (!match) throw new Error(`Cannot parse a GitHub repository from "${value.trim()}"`);
    return { owner: match[1], name: match[2] };
}

export function resolveRepository(repoRoot) {
    if (process.env.GITHUB_REPOSITORY) return parseRepository(process.env.GITHUB_REPOSITORY);
    const remote = execFileSync('git', ['-C', repoRoot, 'remote', 'get-url', 'origin'], { encoding: 'utf8' });
    return parseRepository(remote);
}

export function loadConfig(repoRoot) {
    const file = path.join(repoRoot, 'docs.json');
    if (!existsSync(file)) throw new Error(`docs.json: not found in ${repoRoot}`);
    const config = JSON.parse(readFileSync(file, 'utf8'));
    for (const key of ['title', 'tagline']) {
        if (typeof config[key] !== 'string' || !config[key]) throw new Error(`docs.json: "${key}" is required`);
    }
    return {
        title: config.title, tagline: config.tagline, index: config.index,
        readmes: config.readmes ?? [], pages: config.pages ?? {},
    };
}

const slug = (segment) => segment.toLowerCase().replace(/\./g, '-');

export function pagePath(readme) {
    const dirs = posix.dirname(readme).split('/').slice(1); // drops "src"
    return posix.join('packages', ...dirs.map(slug)) + '.md';
}

const LINK = /(!?)\[([^\]]*)\]\(([^)\s]+)((?:\s+"[^"]*")?)\)/g;

export function rewriteLinks(markdown, { source, target, repository, published }) {
    const { owner, name } = repository;
    const blob = new RegExp(`^https://github\\.com/${owner}/${name}/(?:blob|tree)/[^/]+/(.+)$`);
    const rewrite = (whole, bang, text, href, title) => {
        const [url, anchor] = href.split('#');
        const hash = anchor === undefined ? '' : `#${anchor}`;
        const absolute = blob.exec(url);
        let repoPath;
        if (absolute) repoPath = absolute[1];
        else if (url && !/^[a-z][a-z+.-]*:/i.test(url) && !url.startsWith('/')) {
            repoPath = posix.normalize(posix.join(posix.dirname(source), url));
        } else return whole;
        if (published.has(repoPath)) {
            const link = posix.relative(posix.dirname(target), published.get(repoPath));
            return `${bang}[${text}](${link}${hash}${title})`;
        }
        if (absolute) return whole;
        const base = bang ? `https://raw.githubusercontent.com/${owner}/${name}/main/`
            : `https://github.com/${owner}/${name}/blob/main/`;
        return `${bang}[${text}](${base}${repoPath}${hash}${title})`;
    };
    let fenced = false;
    return markdown.split('\n').map((line) => {
        if (/^\s*(```|~~~)/.test(line)) {
            fenced = !fenced;
            return line;
        }
        return fenced ? line : line.replace(LINK, rewrite);
    }).join('\n');
}

async function expand(cwd, patterns) {
    const files = new Set();
    for (const pattern of patterns) {
        for await (const entry of glob(pattern, { cwd, withFileTypes: true, exclude: (e) => e.name === 'node_modules' })) {
            if (entry.isDirectory()) continue;
            const file = path.relative(cwd, path.join(entry.parentPath, entry.name));
            files.add(file.split(path.sep).join('/'));
        }
    }
    return [...files].sort();
}

const frontMatter = (fields) =>
    `---\n${Object.entries(fields).map(([key, value]) => `${key}: ${value}`).join('\n')}\n---\n\n`;

export async function collect({ repoRoot, outDir, repository }) {
    const config = loadConfig(repoRoot);
    const docsDir = path.join(repoRoot, 'docs');
    if (config.index && existsSync(path.join(docsDir, 'index.md'))) {
        throw new Error(`docs.json: "index" is ${config.index}, but docs/index.md exists too; keep one home page`);
    }

    const sources = new Map();
    const claim = (target, source) => {
        if (sources.has(target)) throw new Error(`${source} and ${sources.get(target)} both map to ${target}`);
        sources.set(target, source);
    };
    if (existsSync(docsDir)) {
        for (const file of await expand(docsDir, ['**/*'])) claim(file, `docs/${file}`);
    }

    const plan = []; // [source, target, front matter, is a package README]
    if (config.index) plan.push([config.index, 'index.md', { slug: '/' }, false]);
    for (const readme of await expand(repoRoot, config.readmes)) plan.push([readme, pagePath(readme), null, true]);
    for (const [target, page] of Object.entries(config.pages)) {
        plan.push([page.source, target, page.label ? { sidebar_label: JSON.stringify(page.label) } : null, false]);
    }
    for (const [source, target] of plan) claim(target, source);
    const published = new Map(plan.map(([source, target]) => [source, target]));

    await rm(outDir, { recursive: true, force: true });
    await mkdir(outDir, { recursive: true });
    if (existsSync(docsDir)) await cp(docsDir, outDir, { recursive: true, dereference: true });

    const categories = new Map();
    for (const [source, target, fields, isPackage] of plan) {
        const text = await readFile(path.join(repoRoot, source), 'utf8');
        const body = rewriteLinks(text, { source, target, repository, published });
        await mkdir(path.dirname(path.join(outDir, target)), { recursive: true });
        await writeFile(path.join(outDir, target), (fields ? frontMatter(fields) : '') + body);
        if (isPackage && posix.dirname(target) !== 'packages') {
            categories.set(posix.dirname(target), posix.dirname(source).split('/').at(-2));
        }
    }
    for (const [dir, label] of categories) {
        await writeFile(path.join(outDir, dir, '_category_.json'), JSON.stringify({ label }, null, 2) + '\n');
    }
    await writeFile(path.join(outDir, '..', 'sources.json'), JSON.stringify(Object.fromEntries(sources), null, 2) + '\n');
    return sources;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
    const website = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
    const repoRoot = path.dirname(website);
    await collect({ repoRoot, outDir: path.join(website, '.generated/docs'), repository: resolveRepository(repoRoot) });
}
