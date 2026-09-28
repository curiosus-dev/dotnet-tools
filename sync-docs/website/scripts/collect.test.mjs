// Synced from https://github.com/curiosus-dev/dotnet-tools, do not edit in place.
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { collect, loadConfig, pagePath, parseRepository, rewriteLinks } from './collect.mjs';

const repository = { owner: 'curiosus-dev', name: 'Curiosus.Utils' };

async function makeRepo(files) {
    const root = await mkdtemp(path.join(tmpdir(), 'collect-'));
    for (const [file, content] of Object.entries(files)) {
        await mkdir(path.dirname(path.join(root, file)), { recursive: true });
        await writeFile(path.join(root, file), content);
    }
    return root;
}

test('parseRepository accepts ssh, https and slug forms', () => {
    for (const input of ['git@github.com:curiosus-dev/Curiosus.Utils.git',
        'https://github.com/curiosus-dev/Curiosus.Utils', 'https://github.com/curiosus-dev/Curiosus.Utils.git\n',
        'curiosus-dev/Curiosus.Utils']) {
        assert.deepEqual(parseRepository(input), repository, input);
    }
    assert.throws(() => parseRepository('not a repo'), /repository/);
});

test('pagePath maps package READMEs under packages/', () => {
    assert.equal(pagePath('src/DAL/Curiosus.DAL/README.md'), 'packages/dal/curiosus-dal.md');
    assert.equal(pagePath('src/Curiosus.Migrations/README.md'), 'packages/curiosus-migrations.md');
});

test('loadConfig requires title and tagline', async () => {
    const missing = await makeRepo({});
    assert.throws(() => loadConfig(missing), /docs\.json/);
    const noTagline = await makeRepo({ 'docs.json': '{"title":"T"}' });
    assert.throws(() => loadConfig(noTagline), /tagline/);
    const ok = await makeRepo({ 'docs.json': '{"title":"T","tagline":"L"}' });
    assert.deepEqual(loadConfig(ok), { title: 'T', tagline: 'L', index: undefined, readmes: [], pages: {} });
});

test('rewriteLinks rewrites published, repository and image links, keeps code and absolute URLs', () => {
    const published = new Map([['src/DAL/Curiosus.DAL/README.md', 'packages/dal/curiosus-dal.md']]);
    const input = [
        '[dal](../../DAL/Curiosus.DAL/README.md#usage)',
        '[abs](https://github.com/curiosus-dev/Curiosus.Utils/blob/main/src/DAL/Curiosus.DAL/README.md)',
        '[file](../../../LICENSE)',
        '![logo](images/logo.png)',
        '[ext](https://example.com/x.md) [anchor](#top)',
        '```md',
        '[code](../../DAL/Curiosus.DAL/README.md)',
        '```',
    ].join('\n');
    const output = rewriteLinks(input, {
        source: 'src/Email/Curiosus.EMail/README.md', target: 'packages/email/curiosus-email.md',
        repository, published,
    });
    assert.equal(output, [
        '[dal](../dal/curiosus-dal.md#usage)',
        '[abs](../dal/curiosus-dal.md)',
        '[file](https://github.com/curiosus-dev/Curiosus.Utils/blob/main/LICENSE)',
        '![logo](https://raw.githubusercontent.com/curiosus-dev/Curiosus.Utils/main/src/Email/Curiosus.EMail/images/logo.png)',
        '[ext](https://example.com/x.md) [anchor](#top)',
        '```md',
        '[code](../../DAL/Curiosus.DAL/README.md)',
        '```',
    ].join('\n'));
});

test('collect assembles docs, index, readmes and pages', async () => {
    const root = await makeRepo({
        'docs.json': JSON.stringify({ title: 'T', tagline: 'L', index: 'README.md',
            readmes: ['src/**/README.md'],
            pages: { 'changelog/dal.md': { source: 'src/DAL/Curiosus.DAL/CHANGELOG.md', label: 'Curiosus.DAL' } } }),
        'README.md': '# Root\n\n[dal](src/DAL/Curiosus.DAL/README.md)\n',
        'docs/guides/a.md': '# A\n',
        'src/DAL/Curiosus.DAL/README.md': '# Curiosus.DAL\n',
        'src/DAL/Curiosus.DAL/CHANGELOG.md': '# Changelog\n',
    });
    const outDir = path.join(root, 'website/.generated/docs');
    const sources = await collect({ repoRoot: root, outDir, repository });

    assert.equal(await readFile(path.join(outDir, 'index.md'), 'utf8'),
        '---\nslug: /\n---\n\n# Root\n\n[dal](packages/dal/curiosus-dal.md)\n');
    assert.equal(await readFile(path.join(outDir, 'guides/a.md'), 'utf8'), '# A\n');
    assert.equal(await readFile(path.join(outDir, 'packages/dal/curiosus-dal.md'), 'utf8'), '# Curiosus.DAL\n');
    assert.deepEqual(JSON.parse(await readFile(path.join(outDir, 'packages/dal/_category_.json'), 'utf8')),
        { label: 'DAL' });
    assert.equal(await readFile(path.join(outDir, 'changelog/dal.md'), 'utf8'),
        '---\nsidebar_label: "Curiosus.DAL"\n---\n\n# Changelog\n');
    assert.equal(sources.get('packages/dal/curiosus-dal.md'), 'src/DAL/Curiosus.DAL/README.md');
    assert.equal(sources.get('guides/a.md'), 'docs/guides/a.md');
    await rm(root, { recursive: true });
});

test('collect fails on a duplicate home page', async () => {
    const root = await makeRepo({
        'docs.json': '{"title":"T","tagline":"L","index":"README.md"}',
        'README.md': '# Root\n', 'docs/index.md': '# Index\n',
    });
    await assert.rejects(collect({ repoRoot: root, outDir: path.join(root, 'out'), repository }),
        /README\.md.*docs\/index\.md/);
});

test('collect fails when two sources map to one page', async () => {
    const root = await makeRepo({
        'docs.json': '{"title":"T","tagline":"L","readmes":["src/**/README.md"]}',
        'src/Email/Curiosus.E.Mail/README.md': '# A\n', 'src/Email/Curiosus.E-Mail/README.md': '# B\n',
    });
    await assert.rejects(collect({ repoRoot: root, outDir: path.join(root, 'out'), repository }),
        /packages\/email\/curiosus-e-mail\.md/);
});
