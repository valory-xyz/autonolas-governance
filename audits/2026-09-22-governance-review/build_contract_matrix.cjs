// Read-only contract matrix: source change per tag interval, deployed instance, live pointer,
// verified build settings, and which source version each deployment matches.
// Usage (from repo root): node audits/2026-09-22-governance-review/build_contract_matrix.cjs
const fs=require('fs'), path=require('path'), crypto=require('crypto');
const {execFileSync}=require('child_process');
const {ethers}=require('ethers');
const ROOT=path.resolve(__dirname,'../..'), OUT=path.join(__dirname,'data','contract-matrix');
fs.mkdirSync(path.join(OUT,'responses'),{recursive:true});
const endpoints=['https://gateway.tenderly.co/public/mainnet','https://eth.drpc.org'];
const key=v=>crypto.createHash('sha256').update(JSON.stringify(v)).digest('hex');
const sha=text=>crypto.createHash('sha256').update(text).digest('hex');
const pin=JSON.parse(fs.readFileSync(path.join(__dirname,'point-1/data/pin.json')));
const globals=JSON.parse(fs.readFileSync(path.join(ROOT,'scripts/deployment/globals_mainnet.json')));
const lineage=JSON.parse(fs.readFileSync(path.join(__dirname,'data/tag-lineage/lineage.json')));
const TAGS=['v1.2.5-post-external-audit','v1.2.5','v1.3.0-pre-external-audit'];

async function rpc(method,params,cache=true){
 const file=path.join(OUT,'responses',key([method,params])+'.json');
 if(cache&&fs.existsSync(file)){const c=JSON.parse(fs.readFileSync(file));if(!c.response.error)return c.response.result;}
 let last;
 for(const endpoint of endpoints){
  try{
   const response=await (await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},
     body:JSON.stringify({jsonrpc:'2.0',id:1,method,params}),signal:AbortSignal.timeout(25000)})).json();
   fs.writeFileSync(file,JSON.stringify({endpoint,method,params,collectedAt:new Date().toISOString(),response},null,2)+'\n');
   if(response.error)throw Error(JSON.stringify(response.error));
   return response.result;
  }catch(e){last=e;}
 }
 throw last;
}
async function explorer(address){
 const url='https://eth.blockscout.com/api/v2/smart-contracts/'+address;
 const file=path.join(OUT,'responses',key(url)+'.json');
 if(fs.existsSync(file))return JSON.parse(fs.readFileSync(file)).response;
 const response=await fetch(url,{headers:{'User-Agent':'governance-review'},signal:AbortSignal.timeout(30000)});
 const body=response.ok?await response.json():{error:response.status};
 fs.writeFileSync(file,JSON.stringify({url,collectedAt:new Date().toISOString(),response:body},null,2)+'\n');
 return body;
}
const hex=ethers.utils.hexValue;
async function call(to,signature,args=[]){
 const iface=new ethers.utils.Interface(['function '+signature]);const fn=Object.values(iface.functions)[0];
 try{
  const value=iface.decodeFunctionResult(fn,await rpc('eth_call',[{to,data:iface.encodeFunctionData(fn,args)},hex(pin.number)]))[0];
  return ethers.BigNumber.isBigNumber(value)?value.toString():value;
 }catch(e){return {error:String(e).slice(0,120)};}
}
// Source text of a repository path at each tag and in the working tree.
const versions={};
function sourceVersions(relative){
 if(versions[relative])return versions[relative];
 const map={};
 for(const tag of TAGS){
  try{map[tag]=sha(execFileSync('git',['show',`${tag}:${relative}`],{cwd:ROOT,encoding:'utf8'}));}catch{map[tag]=null;}
 }
 const file=path.join(ROOT,relative);
 map.checkout=fs.existsSync(file)?sha(fs.readFileSync(file,'utf8')):null;
 versions[relative]=map;return map;
}
const changed=Object.fromEntries(lineage.contracts.map(c=>[c.path,c.edges.map(e=>e.changed)]));

// Remove Solidity comments while respecting string literals, so a source difference can be
// classified as comment-only rather than inferred from a hash mismatch.
function stripComments(text){
 let out='',quote=null;
 for(let i=0;i<text.length;i++){
  const c=text[i],next=text[i+1];
  if(quote){
   out+=c;
   if(c==='\\'){out+=next??'';i++;continue;}
   if(c===quote)quote=null;
   continue;
  }
  if(c==='"'||c==="'"){quote=c;out+=c;continue;}
  if(c==='/'&&next==='/'){while(i<text.length&&text[i]!=='\n')i++;out+='\n';continue;}
  if(c==='/'&&next==='*'){i+=2;while(i<text.length&&!(text[i]==='*'&&text[i+1]==='/'))i++;i++;continue;}
  out+=c;
 }
 return out;
}
const codeOnly=text=>stripComments(text).split('\n').map(l=>l.trim()).filter(Boolean).join('\n');

// L1 contracts of this repository, with the live pointer that establishes use.
const ENTRIES=[
 {name:'OLAS',source:'contracts/OLAS.sol',address:globals.olasAddress},
 {name:'veOLAS',source:'contracts/veOLAS.sol',address:globals.veOLASAddress},
 {name:'wveOLAS',source:'contracts/wveOLAS.sol',address:globals.wveOLASAddress},
 {name:'buOLAS',source:'contracts/buOLAS.sol',address:globals.buOLASAddress},
 {name:'Timelock',source:'contracts/Timelock.sol',address:globals.timelockAddress},
 {name:'GovernorOLAS (first)',source:'contracts/GovernorOLAS.sol',address:globals.governorOneAddress},
 {name:'GovernorOLAS (second)',source:'contracts/GovernorOLAS.sol',address:globals.governorTwoAddress},
 {name:'GovernorOLAS (current)',source:'contracts/GovernorOLAS.sol',address:globals.governorAddress},
 {name:'GuardCM (previous)',source:'contracts/multisigs/GuardCM.sol',address:'0x7bB7998b210cFfE10ca1e41f16341Abe53f76f3a'},
 {name:'GuardCM (current)',source:'contracts/multisigs/GuardCM.sol',address:globals.guardCMAddress},
 {name:'ProcessBridgedDataGnosis',source:'contracts/multisigs/bridge_verifier/ProcessBridgedDataGnosis.sol',address:globals.processBridgedDataGnosisAddress},
 {name:'ProcessBridgedDataPolygon',source:'contracts/multisigs/bridge_verifier/ProcessBridgedDataPolygon.sol',address:globals.processBridgedDataPolygonAddress},
 {name:'ProcessBridgedDataArbitrum',source:'contracts/multisigs/bridge_verifier/ProcessBridgedDataArbitrum.sol',address:globals.processBridgedDataArbitrumAddress},
 {name:'ProcessBridgedDataOptimism',source:'contracts/multisigs/bridge_verifier/ProcessBridgedDataOptimism.sol',address:globals.processBridgedDataOptimismAddress},
 {name:'ProcessBridgedDataWormhole',source:'contracts/multisigs/bridge_verifier/ProcessBridgedDataWormhole.sol',address:null},
 {name:'VoteWeighting',source:'contracts/VoteWeighting.sol',address:globals.voteWeightingAddress},
 {name:'FxERC20RootTunnel',source:'contracts/bridges/FxERC20RootTunnel.sol',address:globals.fxERC20RootTunnelAddress},
 {name:'BridgedERC20',source:'contracts/bridges/BridgedERC20.sol',address:globals.bridgedERC20Address},
 {name:'Burner',source:'contracts/Burner.sol',address:globals.burnerAddress},
 {name:'DeploymentFactory',source:'contracts/DeploymentFactory.sol',address:globals.deploymentFactory},
 {name:'Veto Timelock',source:'contracts/Timelock.sol',address:globals.vetoTimelockAddress||null},
 {name:'Veto Governor',source:'contracts/GovernorOLAS.sol',address:globals.vetoGovernorAddress||null},
];
// Repository contracts deployed on other chains; no L1 instance is verified here.
const L2=[['FxGovernorTunnel','contracts/bridges/FxGovernorTunnel.sol',globals.polygonBridgeMediatorL2,'Polygon'],
 ['HomeMediator','contracts/bridges/HomeMediator.sol',globals.gnosisBridgeMediatorL2,'Gnosis'],
 ['OptimismMessenger','contracts/bridges/OptimismMessenger.sol',globals.optimismMessengerL2Address,'Optimism'],
 ['OptimismMessenger','contracts/bridges/OptimismMessenger.sol',globals.baseMessengerL2Address,'Base'],
 ['OptimismMessenger','contracts/bridges/OptimismMessenger.sol',globals.celoMessengerL2Address,'Celo'],
 ['OptimismMessenger','contracts/bridges/OptimismMessenger.sol',globals.modeMessengerL2Address,'Mode'],
 ['FxERC20ChildTunnel','contracts/bridges/FxERC20ChildTunnel.sol',globals.fxERC20ChildTunnelAddress,'Polygon'],
 ['WormholeMessenger','contracts/bridges/WormholeMessenger.sol',null,'Wormhole route (no address in mainnet configuration)'],
 ['WormholeRelayerTimelock','contracts/bridges/WormholeRelayerTimelock.sol',null,'Wormhole route (no address in mainnet configuration)']];

async function main(){
 if(await rpc('eth_chainId',[],false)!=='0x1')throw Error('Wrong chain');
 const header=await rpc('eth_getBlockByNumber',[hex(pin.number),false]);
 if(header.hash.toLowerCase()!==pin.hash.toLowerCase())throw Error('Pin mismatch');
 // Live pointers that establish which instance the system actually uses.
 const cmGuardSlot=await rpc('eth_getStorageAt',[globals.CM,'0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8',hex(pin.number)]);
 const pointers={
  cmGuard:'0x'+cmGuardSlot.slice(26),
  governorTimelock:await call(globals.governorAddress,'timelock() view returns(address)'),
  governorToken:await call(globals.governorAddress,'token() view returns(address)'),
  guardGovernor:await call(globals.guardCMAddress,'governor() view returns(address)'),
  oldGuardGovernor:await call('0x7bB7998b210cFfE10ca1e41f16341Abe53f76f3a','governor() view returns(address)'),
  wveOLASUnderlying:await call(globals.wveOLASAddress,'ve() view returns(address)'),
  veOLASToken:await call(globals.veOLASAddress,'token() view returns(address)'),
  dispenserVoteWeighting:null,
  timelockRoles:{},
  guardRoutes:{}
 };
 const treasuryTokenomics=await call(globals.treasuryAddress,'tokenomics() view returns(address)');
 const dispenser=await call(treasuryTokenomics,'dispenser() view returns(address)');
 pointers.dispenser=dispenser;
 pointers.dispenserVoteWeighting=await call(dispenser,'voteWeighting() view returns(address)');
 for(const [name,address] of [['governorOne',globals.governorOneAddress],['governorTwo',globals.governorTwoAddress],
   ['governor',globals.governorAddress],['cm',globals.CM]]){
  pointers.timelockRoles[name]={};
  for(const role of ['TIMELOCK_ADMIN_ROLE','PROPOSER_ROLE','EXECUTOR_ROLE','CANCELLER_ROLE'])
   pointers.timelockRoles[name][role]=await call(globals.timelockAddress,'hasRole(bytes32,address) view returns(bool)',[ethers.utils.id(role),address]);
 }
 // Verifier per configured L1 bridge mediator, read from the guard in use.
 for(const [label,l1] of [['Gnosis',globals.AMBContractProxyForeignAddress],['Polygon',globals.fxRootAddress],
   ['Arbitrum',globals.arbitrumInboxAddress],['Optimism',globals.optimismL1CrossDomainMessengerAddress],
   ['Base',globals.baseL1CrossDomainMessengerAddress],['Celo',globals.celoL1CrossDomainMessengerAddress],
   ['Mode',globals.modeL1CrossDomainMessengerAddress],
   // Robinhood Chain (4663) was configured by proposal 16; its inbox is not in the repository configuration.
   ['Robinhood','0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D']]){
  const iface=new ethers.utils.Interface(['function mapBridgeMediatorL1BridgeParams(address) view returns(address verifierL2,address bridgeMediatorL2,uint64 chainId)']);
  try{
   const raw=await rpc('eth_call',[{to:globals.guardCMAddress,data:iface.encodeFunctionData('mapBridgeMediatorL1BridgeParams',[l1])},hex(pin.number)]);
   const d=iface.decodeFunctionResult('mapBridgeMediatorL1BridgeParams',raw);
   pointers.guardRoutes[label]={l1,verifierL2:d.verifierL2,bridgeMediatorL2:d.bridgeMediatorL2,chainId:d.chainId.toString()};
  }catch(e){pointers.guardRoutes[label]={l1,error:String(e).slice(0,120)};}
 }
 const verifiersInUse=new Set(Object.values(pointers.guardRoutes).map(r=>(r.verifierL2||'').toLowerCase()));

 const rows=[];
 for(const entry of ENTRIES){
  const row={contract:entry.name,source:entry.source,
   sourceChangedByInterval:changed[entry.source]||null,
   address:entry.address||null};
  if(entry.address){
   const code=await rpc('eth_getCode',[entry.address,hex(pin.number)]);
   row.runtimeBytes=(code.length-2)/2;
   row.runtimeHash=ethers.utils.keccak256(code);
   const verified=await explorer(entry.address);
   row.verifiedName=verified.name||null;
   row.compiler=verified.compiler_version||null;
   row.optimizationRuns=verified.optimization_runs??null;
   row.evmVersion=verified.evm_version||null;
   row.explorerRuntimeMatchesRpc=verified.deployed_bytecode?verified.deployed_bytecode.toLowerCase()===code.toLowerCase():null;
   const files=verified.file_path?[{file_path:verified.file_path,source_code:verified.source_code},...(verified.additional_sources||[])]:[];
   const own=files.find(f=>(f.file_path||'').endsWith('/'+path.basename(entry.source))||(f.file_path||'')===entry.source);
   const map=sourceVersions(entry.source);
   row.verifiedSourceSha256=own?sha(own.source_code):null;
   row.matchesSourceVersions=own?Object.entries(map).filter(([,h])=>h&&h===sha(own.source_code)).map(([k])=>k):[];
   const checkoutFile=path.join(ROOT,entry.source);
   if(own&&fs.existsSync(checkoutFile)){
    const current=fs.readFileSync(checkoutFile,'utf8');
    row.diffVsCheckout={identical:current===own.source_code,
      codeIdenticalIgnoringComments:codeOnly(current)===codeOnly(own.source_code)};
   }
  }
  rows.push(row);
 }
 // Active status, each tied to the pointer that establishes it.
 const status=(row)=>{
  const a=(row.address||'').toLowerCase();
  if(!row.address)return {status:'not deployed',evidence:'No address in mainnet configuration'};
  if(row.contract.startsWith('Veto'))return {status:'not deployed',evidence:'No veto address in mainnet configuration'};
  if(row.contract==='GovernorOLAS (current)')return {status:'active',evidence:`Timelock roles held; guard.governor()=${pointers.guardGovernor}`};
  if(row.contract.startsWith('GovernorOLAS'))return {status:'superseded',evidence:'Holds no Timelock role at the pin'};
  if(row.contract==='GuardCM (current)')return {status:'active',evidence:`CM Safe guard slot = ${pointers.cmGuard}`};
  if(row.contract==='GuardCM (previous)')return {status:'superseded',evidence:`Not the CM guard; its governor()=${pointers.oldGuardGovernor}`};
  if(row.contract==='Timelock')return {status:'active',evidence:`governor.timelock()=${pointers.governorTimelock}`};
  if(row.contract==='wveOLAS')return {status:'active',evidence:`governor.token()=${pointers.governorToken}`};
  if(row.contract==='veOLAS')return {status:'active',evidence:`wveOLAS.ve()=${pointers.wveOLASUnderlying}`};
  if(row.contract==='OLAS')return {status:'active',evidence:`veOLAS.token()=${pointers.veOLASToken}`};
  if(row.contract==='VoteWeighting')return {status:'active',evidence:`dispenser.voteWeighting()=${pointers.dispenserVoteWeighting}`};
  if(row.contract.startsWith('ProcessBridgedData')){
   const routes=Object.entries(pointers.guardRoutes).filter(([,r])=>(r.verifierL2||'').toLowerCase()===a).map(([k])=>k);
   return routes.length?{status:'active',evidence:'Guard routes: '+routes.join(', ')}
    :{status:'deployed, not referenced by a guard route at the pin',evidence:'No configured L1 mediator points to it'};
  }
  return {status:'deployed; outside the governance control path',evidence:'No governance pointer read for it'};
 };
 for(const row of rows)Object.assign(row,status(row));
 const l2rows=L2.map(([name,source,address,chain])=>({contract:name,source,chain,address:address||null,
   sourceChangedByInterval:changed[source]||null,note:'Not verified in this Ethereum-only collection'}));
 const result={method:'Source-change status from the tag lineage, deployed instances from the mainnet configuration, '
   +'live pointers and code read at the point-1 pin, build metadata and verified sources from Blockscout',
  pin,tags:TAGS,intervals:['v1.2.5-post-external-audit→v1.2.5','v1.2.5→v1.3.0-pre-external-audit','v1.3.0-pre-external-audit→main snapshot'],
  pointers,contracts:rows,otherChains:l2rows,
  limitations:['Explorer-verified source and metadata are provider-reported; runtime bytecode is compared against RPC.',
   'Live pointers establish use at one block; they do not prove a contract is unreachable by other paths.',
   'Addresses come from this repository configuration; an unlisted deployment would not appear.',
   'Contracts on other chains are listed for completeness only and are not verified here.']};
 fs.writeFileSync(path.join(__dirname,'contract-matrix.json'),JSON.stringify(result,null,2)+'\n');
 const flag=v=>v===null?'n/a':v?'yes':'no';
 const md=['# Contract matrix','',
  `Ethereum state at block **${pin.number}** (${new Date(pin.timestamp*1000).toISOString()}). Generated by [build_contract_matrix.cjs](build_contract_matrix.cjs); exact values in [contract-matrix.json](contract-matrix.json).`,'',
  'Source intervals: **A** = `v1.2.5-post-external-audit` → `v1.2.5`, **B** = `v1.2.5` → `v1.3.0-pre-external-audit`, **C** = `v1.3.0-pre-external-audit` → main snapshot.','',
  '| Contract | Source | A | B | C | Deployed instance | Status | Verified source matches | Compiler / runs / EVM |','|---|---|---|---|---|---|---|---|---|'];
 for(const r of rows){
  const [a,b,c]=r.sourceChangedByInterval||[null,null,null];
  md.push(`| ${r.contract} | \`${r.source.replace('contracts/','')}\` | ${flag(a)} | ${flag(b)} | ${flag(c)} | ${r.address?'`'+r.address+'`':'—'} | ${r.status} | ${r.address?(r.matchesSourceVersions.length?r.matchesSourceVersions.join(', '):'no tracked version'):'—'} | ${r.address?`${r.compiler||'?'} / ${r.optimizationRuns??'?'} / ${r.evmVersion||'?'}`:'—'} |`);
 }
 md.push('','## Repository contracts on other chains','',
  'Listed for completeness. This collection verifies Ethereum only.','',
  '| Contract | Source | A | B | C | Chain | Address |','|---|---|---|---|---|---|---|');
 for(const r of l2rows){
  const [a,b,c]=r.sourceChangedByInterval||[null,null,null];
  md.push(`| ${r.contract} | \`${r.source.replace('contracts/','')}\` | ${flag(a)} | ${flag(b)} | ${flag(c)} | ${r.chain} | ${r.address?'`'+r.address+'`':'—'} |`);
 }
 // Notes derived from the collected rows, not written by hand.
 const untracked=rows.filter(r=>r.address&&r.matchesSourceVersions&&r.matchesSourceVersions.length===0);
 const partial=rows.filter(r=>r.matchesSourceVersions&&r.matchesSourceVersions.length&&!r.matchesSourceVersions.includes('checkout'));
 md.push('','## Notes','');
 const label=r=>`${r.contract} (\`${r.address}\`)`;
 const commentOnly=untracked.filter(r=>r.diffVsCheckout&&r.diffVsCheckout.codeIdenticalIgnoringComments);
 const codeDiffers=untracked.filter(r=>!(r.diffVsCheckout&&r.diffVsCheckout.codeIdenticalIgnoringComments));
 if(codeDiffers.length)md.push('- Verified source matches none of the three tags, and the working-tree source differs in code, so these were deployed from an earlier revision: '
  +codeDiffers.map(label).join(', ')+'.');
 if(commentOnly.length)md.push('- Verified source matches no tracked version only because of comments; the executable source is identical to the working tree once comments and whitespace are removed: '
  +commentOnly.map(label).join(', ')+'.');
 for(const r of partial){
  const d=r.diffVsCheckout;
  const how=d&&d.codeIdenticalIgnoringComments
   ? 'the only differences from the working tree are comments: the executable source is identical once comments and whitespace are removed'
   : 'the working-tree source differs in code, not only in comments';
  md.push(`- ${r.contract} (\`${r.address}\`) matches ${r.matchesSourceVersions.join(', ')}; ${how}.`);
 }
 md.push(`- Every verified runtime listed above matches the bytecode returned by RPC at the pin (${rows.filter(r=>r.explorerRuntimeMatchesRpc===true).length} of ${rows.filter(r=>r.address).length} deployed entries).`);
 md.push('','## Limitations','',...result.limitations.map(x=>'- '+x),'');
 fs.writeFileSync(path.join(__dirname,'CONTRACT_MATRIX.md'),md.join('\n'));
 console.log(md.join('\n'));
}
main().catch(e=>{console.error(e);process.exitCode=1;});
