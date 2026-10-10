// ADR015 closed modified-library policy. These pins qualify the project delivery,
// not recipients' ABI-compatible replacement DLLs. No generic modified bypass.
import fs from 'node:fs';
import path from 'node:path';

export const COUPLED_ID = 'jsbsim-coupled-midpoint-v1';
export const COUPLED_VARIANT = 'jsbsim-1.3.1-event-aware-coupled-midpoint-v1';
const ROOT = 'third_party/patches/jsbsim/event-aware-coupled-midpoint-v1';
const IDENTITY_PATH = ROOT + '/identity.json';
const IDENTITY_SHA = "8b3793f79e86760795a0cf5ea3454a62bbdc49ed82bbf9c1a5adc6e007ed1f00";
const NOTICE_PATH = "tools/export/jsbsim-coupled-midpoint/MODIFICATIONS.md";
const NOTICE_SHA = "e550d82f1ff0dd5b545fd0abc2410e2047edcb5495b7967ba003332da7238035";
const BUILD_PATH = "tools/export/jsbsim-coupled-midpoint/BUILD.md";
const BUILD_SHA = "d5db0dfa422010d78c45dc590f3a57f5c134cbc0ae4a088ef4d30683f1206f76";
const EXPECTED = {
  "acquisition_sha256": "df57467a831cfa3ee3cadcb98d8291ce56bb11976e35dd9e93c94201ff1420d5",
  "bundle_files": 293,
  "changes": [
    {
      "after": {
        "bytes": 49088,
        "member": "vendor/src/models/propulsion/FGPiston.cpp",
        "sha256": "509097a76de13c00ff29c6e86e4c475aa6cb14694c3091607be72acc92f730b9"
      },
      "before": {
        "bytes": 41430,
        "member": "patches/event-aware-coupled-midpoint-v1/FGPiston.cpp.before",
        "sha256": "1f69e3caa742cbf24e5467245e1520293460975f003c7b8de8577262329ba836"
      },
      "path": "src/models/propulsion/FGPiston.cpp"
    },
    {
      "after": {
        "bytes": 19520,
        "member": "vendor/src/models/propulsion/FGPiston.h",
        "sha256": "1272b70745d30748f70ee9d39b96ca6993581ee4aa23ea165b0c3909ec9e7b89"
      },
      "before": {
        "bytes": 19045,
        "member": "patches/event-aware-coupled-midpoint-v1/FGPiston.h.before",
        "sha256": "caf5d49ae05c286a5deb27c4087216fa8264ef94d0c388af3c45418389915494"
      },
      "path": "src/models/propulsion/FGPiston.h"
    },
    {
      "after": {
        "bytes": 54782,
        "member": "vendor/src/models/propulsion/FGPropeller.cpp",
        "sha256": "e0ff11682070f2fa5a40ed7f14dbfcf56719a186089eb03185af8cdf9227d9f4"
      },
      "before": {
        "bytes": 18319,
        "member": "patches/event-aware-coupled-midpoint-v1/FGPropeller.cpp.before",
        "sha256": "61c207fec6a80a48a142e3b29f2ef0a3210158e4ab4a0d2929835b72c99fe4d7"
      },
      "path": "src/models/propulsion/FGPropeller.cpp"
    },
    {
      "after": {
        "bytes": 14960,
        "member": "vendor/src/models/propulsion/FGPropeller.h",
        "sha256": "730819eba6e87b94c75c8e02606f55a8006e54822f8f8f669f24d2941b1be6a5"
      },
      "before": {
        "bytes": 13232,
        "member": "patches/event-aware-coupled-midpoint-v1/FGPropeller.h.before",
        "sha256": "2330dad95c6636d1e834d9b82e71f37b0751887e7de406936befe4822b74a14d"
      },
      "path": "src/models/propulsion/FGPropeller.h"
    }
  ],
  "materializer_sha256": "6774634a5b930bf18dd718e2a63661dfad6f4ca0064de4655ad202cc00722867",
  "modified_vendor_files": 4,
  "recipe_sha256": "e7dc28e9267ff5b095a857b0f9a2464af26029bedb5a6520233d50cabe0dbf9b",
  "schema_version": 1,
  "source_archive_bytes": 3922800,
  "source_archive_sha256": "39181ba60397fe5c2ad74d14c02150a2488bc8c96dc29529a0a0396cfc1e3b2d",
  "source_variant": "jsbsim-1.3.1-event-aware-coupled-midpoint-v1",
  "upstream_commit": "3b25f25e49b42d0489c04ac805674fc1450ca579",
  "upstream_inventory_sha256": "083ba0601443c0d24b6641fd04794840cd3054fb7adc98e47f2fb7a1a1048fc5",
  "vendor_files": 279,
  "vendor_tree_sha256": "ea399a43032235d242f08f9d03cc20aee94b9d934405102514a46e529bd31aaa"
};
const plain = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const keys = (x, names) => plain(x) && Object.keys(x).length===names.length && [...names].sort().every((k,i)=>Object.keys(x).sort()[i]===k);
function exact(a,b) {
  if (Array.isArray(b)) return Array.isArray(a) && a.length===b.length && a.every((x,i)=>exact(x,b[i]));
  if (plain(b)) return keys(a,Object.keys(b)) && Object.keys(b).every(k=>exact(a[k],b[k]));
  return a===b;
}
export function auditCoupledIdentity(value) {
  // Exact schema1 describes this schema3 archive. Equality closes every key,
  // type, ordered before/after roster, member spelling, byte count and digest.
  return exact(value, EXPECTED) ? [] : [COUPLED_ID + ': unsupported closed schema3 source identity'];
}
function readChecked(root, relative, expected, errors, context, checkedFile) {
  if (!root) { errors.push(context + ': repository/package root required'); return null; }
  if (checkedFile(root, relative, errors, context, expected) !== expected) return null;
  try { return fs.readFileSync(path.join(fs.realpathSync(root),relative)); }
  catch { errors.push(context + ': missing or unreadable source record'); return null; }
}
export function auditCoupledRegister(entry,{repoRoot,errors,checkedFile}) {
  const p=entry.library_policy;
  if (!keys(p,['linkage','source_archive_sha256','source_delivery','modification_policy','release_policy','source_identity']) ||
      p.release_policy!==COUPLED_ID || p.linkage!=='dynamic' ||
      !exact(p.source_identity,{path:IDENTITY_PATH,sha256:IDENTITY_SHA}) ||
      p.source_archive_sha256!==EXPECTED.source_archive_sha256 ||
      entry.version!=='1.3.1' || entry.source?.revision!==EXPECTED.upstream_commit ||
      entry.source?.archive_sha256!==EXPECTED.acquisition_sha256 || entry.class!=='runtime' ||
      entry.redistribution!=='conditional' || entry.evidence!=='source-verified' ||
      entry.license!=="LGPL-2.1-or-later; bundled MIT components" ||
      !exact(entry.obligations,["retain-notices", "stage-third-party-notices", "include-corresponding-source", "allow-library-replacement", "permit-reverse-engineering", "record-modifications"]) ||
      p.modification_policy!=="Flight-simulator project contributors changed FGPiston.cpp, FGPiston.h, FGPropeller.cpp and FGPropeller.h on 2026-10-09 under retained LGPL-2.1-or-later grants. Piston notices renewed without numerical token changes; reviewed source identity and dated MODIFICATIONS.md required. Original copyright/embedded grants remain in force; no aircraft qualification claim.")
    errors.push(COUPLED_ID + ': reserved modified release policy/identity mismatch');
  const notices=entry.notice_files;
  const expectedNotices=[
  {
    "path": "third_party/licenses/notices/JSBSim-COPYING.txt",
    "sha256": "dc626520dcd53a22f727af3ee42c770e56c97a64fe3adb063799d8ab032fe551"
  },
  {
    "path": "third_party/licenses/notices/JSBSim-Expat-COPYING.txt",
    "sha256": "8c6b5b6de8fae20b317f4992729abc0e520bfba4c7606cd1e9eeb87418eebdec"
  },
  {
    "path": "third_party/licenses/notices/JSBSim-GeographicLib-LICENSE.txt",
    "sha256": "90d25298be0c5d7f5219ae20009d18910150b3a4ea0ca86dda5df04cfb8d3823"
  },
  {
    "path": "tools/export/jsbsim-coupled-midpoint/MODIFICATIONS.md",
    "sha256": "e550d82f1ff0dd5b545fd0abc2410e2047edcb5495b7967ba003332da7238035"
  }
];
  if (!Array.isArray(notices) || notices.length!==4 || !expectedNotices.every(n=>notices.filter(v=>v?.path===n.path && v?.sha256===n.sha256).length===1))
    errors.push(COUPLED_ID + ': closed upstream and dated modification notices required');
  if (!repoRoot) { errors.push(COUPLED_ID + ': repository root required for modified source review'); return; }
  const raw=readChecked(repoRoot,IDENTITY_PATH,IDENTITY_SHA,errors,COUPLED_ID+' repository identity',checkedFile);
  if (raw) {
    try { errors.push(...auditCoupledIdentity(JSON.parse(raw.toString('utf8')))); }
    catch { errors.push(COUPLED_ID + ': unreadable closed source identity'); }
  }
  for (const [name,hash] of [
    [ROOT+'/patches/event-aware-coupled-midpoint-v1/recipe.json',EXPECTED.recipe_sha256],
    [ROOT+'/upstream-file-inventory.json',EXPECTED.upstream_inventory_sha256],
    ['tools/export/jsbsim-coupled-midpoint/materialize.py',EXPECTED.materializer_sha256],
    [NOTICE_PATH,NOTICE_SHA],[BUILD_PATH,BUILD_SHA]])
    checkedFile(repoRoot,name,errors,COUPLED_ID+' reviewed source '+name,hash);
}
export function auditCoupledRelease(entry,component,{repoRoot,packageRoot,componentFiles,errors,checkedFile}) {
  if (component.modified!==true || component.source_variant!==COUPLED_VARIANT)
    errors.push(COUPLED_ID + ': modified:true and exact source variant required');
  const identity=componentFiles.get(component.source_identity);
  if (!identity || identity.role!=='evidence' || identity.sha256!==IDENTITY_SHA)
    errors.push(COUPLED_ID + ': exact staged source identity evidence required');
  else {
    const raw=readChecked(packageRoot,identity.path,IDENTITY_SHA,errors,COUPLED_ID+' staged identity',checkedFile);
    const original=readChecked(repoRoot,IDENTITY_PATH,IDENTITY_SHA,errors,COUPLED_ID+' repository identity',checkedFile);
    if (raw && original && !raw.equals(original)) errors.push(COUPLED_ID + ': staged/repository identity bytes differ');
    if (raw) {
      try { errors.push(...auditCoupledIdentity(JSON.parse(raw.toString('utf8')))); }
      catch { errors.push(COUPLED_ID + ': unreadable staged source identity'); }
    }
  }
  const notice=componentFiles.get(component.modification_notice);
  const mappings=Array.isArray(component.notices)?component.notices:[];
  if (!notice || notice.role!=='notice' || notice.sha256!==NOTICE_SHA ||
      mappings.filter(x=>x?.register_path===NOTICE_PATH && x?.package_path===notice.path).length!==1)
    errors.push(COUPLED_ID + ': exact dated modification notice mapping required');
  const build=componentFiles.get(component.build_instructions);
  if (!build || build.role!=='build-instructions' || build.sha256!==BUILD_SHA)
    errors.push(COUPLED_ID + ': exact schema3 build/replacement instructions required');
  const source=componentFiles.get(component.source_archive);
  // Generic file integrity has already checked containment, regular-file status
  // and the reviewed archive digest. Only stat after that same safety gate.
  if (source && source.role==='source' && checkedFile(packageRoot,source.path,errors,COUPLED_ID+' archive',EXPECTED.source_archive_sha256)===EXPECTED.source_archive_sha256) {
    try { if (fs.statSync(path.join(fs.realpathSync(packageRoot),source.path)).size!==EXPECTED.source_archive_bytes) errors.push(COUPLED_ID + ': corresponding-source archive byte count mismatch'); }
    catch { errors.push(COUPLED_ID + ': missing source archive byte count'); }
  }
}
