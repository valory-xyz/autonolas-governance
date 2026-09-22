// Offline reconciliation of committed proposal artifacts and collected chain evidence.
const fs=require('fs'),path=require('path'),{ethers}=require('ethers');
const {out,save,iface}=require('./collect_chain.cjs');
const read=n=>JSON.parse(fs.readFileSync(path.join(out,n)));
const proposals=read('proposals.json'),events=read('events.json'),receipts=read('event_receipts.json');
const snaps=read('snapshots.json');
const id=(t,v,c,d)=>ethers.BigNumber.from(ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(['address[]','uint256[]','bytes[]','bytes32'],[t,v,c,ethers.utils.id(d)]))).toString();
const result={artifacts:{},receiptVerification:[],snapshots:[],sourceVerification:{}};
for(const n of [11,15]){
 const folder=path.resolve(__dirname,'../../../scripts/proposals/proposal_'+n);
 const calls=JSON.parse(fs.readFileSync(path.join(folder,'calldata.json')));
 const description=fs.readFileSync(path.join(folder,'description.txt'),'utf8');
 const localId=id(calls.map(x=>x.target),calls.map(x=>x.value),calls.map(x=>x.calldata),description);
 const p=proposals.find(x=>n===11?x.args.description.startsWith('Olas Governance and'):x.args.proposalId===localId);
 const a=p.args;
 const comparisons=Array.from({length:Math.max(calls.length,a.targets.length)},(_,i)=>({index:i,
  local:calls[i]||null,chain:a.targets[i]?{target:a.targets[i],value:a.values[i],calldata:a.calldatas[i]}:null,
  equal:!!calls[i]&&calls[i].target.toLowerCase()===a.targets[i].toLowerCase()&&calls[i].value===a.values[i]&&calls[i].calldata.toLowerCase()===a.calldatas[i].toLowerCase()}));
 result.artifacts[n]={localId,onchainId:a.proposalId,recomputedOnchainId:id(a.targets,a.values,a.calldatas,a.description),descriptionEqual:description===a.description,
  localCallCount:calls.length,onchainCallCount:a.targets.length,comparisons,localDescription:description,onchainDescription:a.description,
  creationTransaction:p.tx,execution:events.find(e=>e.event==='ProposalExecuted'&&e.args.proposalId===a.proposalId)};
 if(result.artifacts[n].recomputedOnchainId!==a.proposalId)throw Error('Onchain proposal ID mismatch');
}
for(const event of events.filter(e=>receipts[e.tx])){
 const r=receipts[event.tx];const log=r.logs.find(l=>parseInt(l.logIndex,16)===event.logIndex);
 let valid=false;
 if(log){const parsed=iface.parseLog(log);valid=r.status==='0x1'&&parseInt(r.blockNumber,16)===event.block&&log.address.toLowerCase()===event.address.toLowerCase()&&parsed.name===event.event&&JSON.stringify(Object.fromEntries(parsed.eventFragment.inputs.map((x,i)=>[x.name,clean(parsed.args[i])])))===JSON.stringify(event.args);}
 result.receiptVerification.push({transaction:event.tx,logIndex:event.logIndex,event:event.event,valid});
}
function clean(v){if(ethers.BigNumber.isBigNumber(v))return v.toString();if(Array.isArray(v))return v.map(clean);return v;}
for(const s of snaps)result.snapshots.push({block:s.block,timestamp:new Date(parseInt(s.blockInfo.timestamp,16)*1000).toISOString(),parameters:s.governors.governor,minDelay:s.minDelay,treasuryOwner:s.treasuryOwner,guard:s.guardSlot,roles:s.roles,
 votes:s.votes,supply:s.pastTotalSupply,quorumPreviousBlock:s.quorumPreviousBlock});
const verified=read('explorer/verified-governor.json').response;
const sources=[{file_path:verified.file_path,source_code:verified.source_code},...verified.additional_sources];
result.sourceVerification.files=sources.map(s=>({path:s.file_path,equalsCheckout:fs.existsSync(s.file_path)&&fs.readFileSync(s.file_path,'utf8')===s.source_code}));
const runtime=fs.readFileSync(path.join(out,'governor-runtime.hex'),'utf8').trim();
result.sourceVerification.explorerRuntimeMatchesRpc=verified.deployed_bytecode.toLowerCase()===runtime.toLowerCase();
const artifactPath='/tmp/ai-review-governance-unit-out/GovernorOLAS.sol/GovernorOLAS.json';
if(fs.existsSync(artifactPath)){
 const compiled=JSON.parse(fs.readFileSync(artifactPath));
 const normalize=code=>{
  let b=Buffer.from(code.replace(/^0x/,''),'hex');
  for(const entries of Object.values(compiled.deployedBytecode.immutableReferences))for(const entry of entries)b.fill(0,entry.start,entry.start+entry.length);
  const metadataLength=b.readUInt16BE(b.length-2);return b.subarray(0,b.length-metadataLength-2).toString('hex');
 };
 result.sourceVerification.compiledExecutableMatchesExcludingMetadataAndImmutableSlots=normalize(compiled.deployedBytecode.object)===normalize(runtime);
 result.sourceVerification.bytecodeComparisonLimit='Compiler-declared immutable slots and CBOR metadata excluded; live token getter independently checked. Not a full constructor-byte equality claim.';
}
save('analysis.json',result);
if(result.receiptVerification.some(x=>!x.valid))throw Error('Receipt mismatch');
console.log('Verified',result.receiptVerification.length,'explorer events against RPC receipts');
for(const [n,a] of Object.entries(result.artifacts))console.log('Proposal',n,JSON.stringify({local:a.localCallCount,onchain:a.onchainCallCount,descriptionEqual:a.descriptionEqual,differingIndices:a.comparisons.filter(x=>!x.equal).map(x=>x.index),executed:a.execution.tx}));
console.log(result.snapshots.map(x=>({block:x.block,time:x.timestamp,threshold:x.parameters.proposalThreshold,quorumNumerator:x.parameters.quorumNumerator})));
