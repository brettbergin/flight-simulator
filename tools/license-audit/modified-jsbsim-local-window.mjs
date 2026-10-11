// ADR024 closed modified-library source policy (source-only qualification). These pins qualify the project delivery,
// not recipients' ABI-compatible replacement DLLs. No generic modified bypass.
import fs from 'node:fs';
import path from 'node:path';

export const LOCAL_WINDOW_ID = 'jsbsim-coupled-midpoint-local-window-v2';
export const LOCAL_WINDOW_VARIANT = 'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2';
const ROOT = 'third_party/patches/jsbsim/event-aware-coupled-midpoint-local-window-v2';
const IDENTITY_PATH = ROOT + '/identity.json';
const IDENTITY_SHA = "73000fbab720fe8361d65de049a027b6e280e5f835eedaab92df0bdd1746d770";
const NOTICE_PATH = "tools/export/jsbsim-coupled-midpoint-local-window/MODIFICATIONS.md";
const NOTICE_SHA = "ebbe816e388cd2c21466ea791056b79ca2c77654b2ff8c68dd0bf6ef1deffa37";
const BUILD_PATH = "tools/export/jsbsim-coupled-midpoint-local-window/BUILD.md";
const BUILD_SHA = "c4a6329c3c9c39439947b49c2d1c0c7d29f0150c8441df26325430c23e3bcda5";
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
        "member": "patches/event-aware-coupled-midpoint-local-window-v2/FGPiston.cpp.before",
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
        "member": "patches/event-aware-coupled-midpoint-local-window-v2/FGPiston.h.before",
        "sha256": "caf5d49ae05c286a5deb27c4087216fa8264ef94d0c388af3c45418389915494"
      },
      "path": "src/models/propulsion/FGPiston.h"
    },
    {
      "after": {
        "bytes": 57205,
        "member": "vendor/src/models/propulsion/FGPropeller.cpp",
        "sha256": "bc8414bfd86d482e32c7c3edd5e73352ffa7209b9daec74cf6ac19f1421a6d17"
      },
      "before": {
        "bytes": 18319,
        "member": "patches/event-aware-coupled-midpoint-local-window-v2/FGPropeller.cpp.before",
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
        "member": "patches/event-aware-coupled-midpoint-local-window-v2/FGPropeller.h.before",
        "sha256": "2330dad95c6636d1e834d9b82e71f37b0751887e7de406936befe4822b74a14d"
      },
      "path": "src/models/propulsion/FGPropeller.h"
    }
  ],
  "materializer_sha256": "645fe299d160137b1e7dd4ace2d077ca26389253fa9242c4be5182451d01f42a",
  "modified_vendor_files": 4,
  "recipe_sha256": "603c3f042d8225a32ce067eaaa1deca00ac327240eef6538e7a9e340df3cbe4c",
  "schema_version": 1,
  "source_archive_bytes": 3926768,
  "source_archive_sha256": "7341b8d797082efb2107f12511ac0ecab09fde66423c8bb3b6cd329ddff28177",
  "source_variant": "jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2",
  "upstream_commit": "3b25f25e49b42d0489c04ac805674fc1450ca579",
  "upstream_inventory_sha256": "083ba0601443c0d24b6641fd04794840cd3054fb7adc98e47f2fb7a1a1048fc5",
  "vendor_files": 279,
  "vendor_tree_sha256": "97652c3d57537b5eede8216b3f696a60e260f3a8a15672f4b65b4d93a887c237"
};
const plain = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const keys = (x, names) => plain(x) && Object.keys(x).length===names.length && [...names].sort().every((k,i)=>Object.keys(x).sort()[i]===k);
function exact(a,b) {
  if (Array.isArray(b)) return Array.isArray(a) && a.length===b.length && a.every((x,i)=>exact(x,b[i]));
  if (plain(b)) return keys(a,Object.keys(b)) && Object.keys(b).every(k=>exact(a[k],b[k]));
  return a===b;
}
export function auditLocalWindowIdentity(value) {
  // Exact schema1 describes this schema3 archive. Equality closes every key,
  // type, ordered before/after roster, member spelling, byte count and digest.
  return exact(value, EXPECTED) ? [] : [LOCAL_WINDOW_ID + ': unsupported closed schema3 source identity'];
}
function readChecked(root, relative, expected, errors, context, checkedFile) {
  if (!root) { errors.push(context + ': repository/package root required'); return null; }
  if (checkedFile(root, relative, errors, context, expected) !== expected) return null;
  try { return fs.readFileSync(path.join(fs.realpathSync(root),relative)); }
  catch { errors.push(context + ': missing or unreadable source record'); return null; }
}
export function auditLocalWindowRegister(entry,{repoRoot,errors,checkedFile}) {
  const p=entry.library_policy;
  if (!keys(p,['linkage','source_archive_sha256','source_delivery','modification_policy','release_policy','source_identity']) ||
      p.release_policy!==LOCAL_WINDOW_ID || p.linkage!=='dynamic' ||
      !exact(p.source_identity,{path:IDENTITY_PATH,sha256:IDENTITY_SHA}) ||
      p.source_archive_sha256!==EXPECTED.source_archive_sha256 ||
      entry.version!=='1.3.1' || entry.source?.revision!==EXPECTED.upstream_commit ||
      entry.source?.archive_sha256!==EXPECTED.acquisition_sha256 || entry.class!=='runtime' ||
      entry.redistribution!=='conditional' || entry.evidence!=='source-verified' ||
      entry.license!=="LGPL-2.1-or-later; bundled MIT components" ||
      !exact(entry.obligations,["retain-notices", "stage-third-party-notices", "include-corresponding-source", "allow-library-replacement", "permit-reverse-engineering", "record-modifications"]) ||
      p.modification_policy!=="Flight-simulator project contributors inherited the four ADR015 propulsion modifications dated 2026-10-09 and changed only FGPropeller.cpp further on 2026-10-11 under retained LGPL-2.1-or-later grants for the ADR024 bounded local decay window. Original copyright/embedded grants remain in force; no aircraft qualification claim.")
    errors.push(LOCAL_WINDOW_ID + ': reserved modified release policy/identity mismatch');
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
    "path": "tools/export/jsbsim-coupled-midpoint-local-window/MODIFICATIONS.md",
    "sha256": "ebbe816e388cd2c21466ea791056b79ca2c77654b2ff8c68dd0bf6ef1deffa37"
  }
];
  if (!Array.isArray(notices) || notices.length!==4 || !expectedNotices.every(n=>notices.filter(v=>v?.path===n.path && v?.sha256===n.sha256).length===1))
    errors.push(LOCAL_WINDOW_ID + ': closed upstream and dated modification notices required');
  if (!repoRoot) { errors.push(LOCAL_WINDOW_ID + ': repository root required for modified source review'); return; }
  const raw=readChecked(repoRoot,IDENTITY_PATH,IDENTITY_SHA,errors,LOCAL_WINDOW_ID+' repository identity',checkedFile);
  if (raw) {
    try { errors.push(...auditLocalWindowIdentity(JSON.parse(raw.toString('utf8')))); }
    catch { errors.push(LOCAL_WINDOW_ID + ': unreadable closed source identity'); }
  }
  for (const [name,hash] of [
    [ROOT+'/patches/event-aware-coupled-midpoint-local-window-v2/recipe.json',EXPECTED.recipe_sha256],
    [ROOT+'/upstream-file-inventory.json',EXPECTED.upstream_inventory_sha256],
    ['tools/export/jsbsim-coupled-midpoint-local-window/materialize.py',EXPECTED.materializer_sha256],
    [NOTICE_PATH,NOTICE_SHA],[BUILD_PATH,BUILD_SHA]])
    checkedFile(repoRoot,name,errors,LOCAL_WINDOW_ID+' reviewed source '+name,hash);
}
export function auditLocalWindowRelease(entry,component,{repoRoot,packageRoot,componentFiles,errors,checkedFile}) {
  if (component.modified!==true || component.source_variant!==LOCAL_WINDOW_VARIANT)
    errors.push(LOCAL_WINDOW_ID + ': modified:true and exact source variant required');
  const identity=componentFiles.get(component.source_identity);
  if (!identity || identity.role!=='evidence' || identity.sha256!==IDENTITY_SHA)
    errors.push(LOCAL_WINDOW_ID + ': exact staged source identity evidence required');
  else {
    const raw=readChecked(packageRoot,identity.path,IDENTITY_SHA,errors,LOCAL_WINDOW_ID+' staged identity',checkedFile);
    const original=readChecked(repoRoot,IDENTITY_PATH,IDENTITY_SHA,errors,LOCAL_WINDOW_ID+' repository identity',checkedFile);
    if (raw && original && !raw.equals(original)) errors.push(LOCAL_WINDOW_ID + ': staged/repository identity bytes differ');
    if (raw) {
      try { errors.push(...auditLocalWindowIdentity(JSON.parse(raw.toString('utf8')))); }
      catch { errors.push(LOCAL_WINDOW_ID + ': unreadable staged source identity'); }
    }
  }
  const notice=componentFiles.get(component.modification_notice);
  const mappings=Array.isArray(component.notices)?component.notices:[];
  if (!notice || notice.role!=='notice' || notice.sha256!==NOTICE_SHA ||
      mappings.filter(x=>x?.register_path===NOTICE_PATH && x?.package_path===notice.path).length!==1)
    errors.push(LOCAL_WINDOW_ID + ': exact dated modification notice mapping required');
  const build=componentFiles.get(component.build_instructions);
  if (!build || build.role!=='build-instructions' || build.sha256!==BUILD_SHA)
    errors.push(LOCAL_WINDOW_ID + ': exact schema3 build/replacement instructions required');
  const source=componentFiles.get(component.source_archive);
  // Generic file integrity has already checked containment, regular-file status
  // and the reviewed archive digest. Only stat after that same safety gate.
  if (source && source.role==='source' && checkedFile(packageRoot,source.path,errors,LOCAL_WINDOW_ID+' archive',EXPECTED.source_archive_sha256)===EXPECTED.source_archive_sha256) {
    try { if (fs.statSync(path.join(fs.realpathSync(packageRoot),source.path)).size!==EXPECTED.source_archive_bytes) errors.push(LOCAL_WINDOW_ID + ': corresponding-source archive byte count mismatch'); }
    catch { errors.push(LOCAL_WINDOW_ID + ': missing source archive byte count'); }
  }
}
