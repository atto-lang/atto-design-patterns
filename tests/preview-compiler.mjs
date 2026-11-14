// Optional negative compiled-Atto admission test, not a parser/linker parity claim.
// Requires native ATTOC and a pinned ATTO_COMPILER_HEAD; no compiler downloaded.
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,rmSync,existsSync} from 'node:fs';
import {dirname,resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const attoc=resolve(process.env.ATTOC||'missing-attoc');
assert.match(process.env.ATTO_COMPILER_HEAD||'',/^[a-f0-9]{40}$/);
assert.ok(existsSync(attoc),'ATTOC native compiler executable missing');
const catalog=JSON.parse(readFileSync(join(root,'patterns/catalog.json'),'utf8'));
assert.equal(catalog.schema,'atto.patterns.catalog.v1');
const tmp=mkdtempSync(join(tmpdir(),'atto-pattern-'));
try {
 for(const item of catalog.examples) {
   assert.equal(item.status,'syntax-preview');
   assert.equal(item.execution,'not_executed');
   assert.match(item.path,/^patterns\/[a-z0-9-]+\.atto$/);
   const artifact=join(tmp,item.id+'.wasm');
   const result=spawnSync(attoc,[join(root,item.path),'-o',artifact],{encoding:'utf8',timeout:60000,maxBuffer:1<<20});
   assert.equal(result.status,1,'syntax preview unexpectedly emitted an executable guest; revisit evidence classification');
   assert.ok(!existsSync(artifact),'unsupported receiver method generated Wasm');
   assert.match(result.stderr,/E_[A-Z_]+/,'compiler must emit a structured diagnostic');
   console.log(JSON.stringify({kind:'ACTOR_RECEIVER_NOT_EXECUTABLE',compiler_head:process.env.ATTO_COMPILER_HEAD,example:item.id,diagnostic:result.stderr.trim().slice(0,240),status:'passed'}));
 }
}finally {rmSync(tmp,{recursive:true,force:true});}
