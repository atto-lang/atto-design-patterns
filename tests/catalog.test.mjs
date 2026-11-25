import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, lstatSync} from 'node:fs';
import {resolve, dirname, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const catalog = JSON.parse(readFileSync(resolve(root, 'patterns/catalog.json'), 'utf8'));
function validate(data) {
  assert.equal(data.schema, 'atto.patterns.catalog.v1');
  assert.ok(Array.isArray(data.examples) && data.examples.length > 0);
  const ids = new Set();
  for (const item of data.examples) {
    assert.match(item.id, /^[a-z][a-z0-9-]+$/);
    assert.ok(!ids.has(item.id), 'duplicate example ID');
    ids.add(item.id);
    assert.equal(item.status, 'syntax-preview');
    assert.equal(item.execution, 'not_executed');
    assert.match(item.path, /^patterns\/[a-z0-9-]+\.atto$/);
    assert.ok(Array.isArray(item.required_features) && item.required_features.length > 0);
    const target = resolve(root, item.path);
    assert.ok(target.startsWith(root + sep), 'example outside repository');
    assert.ok(lstatSync(target).isFile() && !lstatSync(target).isSymbolicLink());
    const source = readFileSync(target, 'utf8');
    assert.ok(source.length > 30 && source.length < 65536);
    assert.match(source, /SYNTAX PREVIEW ONLY/);
    assert.doesNotMatch(source, /\.ores\b/);
  }
}
test('catalog only publishes safe, explicitly unexecuted .atto patterns', () => validate(catalog));
test('catalog fails closed on unsupported execution claims and unsafe paths', () => {
  for (const change of [
    {execution:'passed'}, {status:'verified-guest'},
    {path:'patterns/../../oops.atto'}, {path:'patterns/legacy.ores'}
  ]) assert.throws(() => validate({...catalog, examples:[{...catalog.examples[0],...change}]}));
  assert.throws(() => validate({...catalog,examples:[catalog.examples[0],catalog.examples[0]]}));
});
test('two actors have distinct typed mtd receivers and sealed state access', () => {
  const source = readFileSync(resolve(root, catalog.examples[0].path), 'utf8');
  assert.match(source, /use namespace workers;/);
  assert.match(source, /declare actor Foo1;/);
  assert.match(source, /declare actor Foo2;/);
  for (const actor of ['Foo1','Foo2']) {
    assert.match(source,new RegExp('mtd \\(mut self: '+actor+'\\)'));
    assert.match(source,new RegExp('mtd \\(self: '+actor+'\\)'));
  }
  assert.match(source, /handle_state\(critical-read/);
  assert.match(source, /handle_state\(critical-write/);
  assert.doesNotMatch(source, /fnc\s*\(.*self/);
});
