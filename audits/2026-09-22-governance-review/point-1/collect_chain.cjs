// Read-only Ethereum evidence collector. No wallet or transaction submission methods.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { ethers } = require('ethers');
const out = path.join(__dirname, 'data');
fs.mkdirSync(path.join(out, 'rpc'), {recursive:true});
const endpoint = 'https://ethereum-rpc.publicnode.com';
const addr = {
  governor:'0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6',
  oldGovernor:'0x8E84B5055492901988B831817e4Ace5275A3b401',
  firstGovernor:'0x34C895f302D0b5cf52ec0Edd3945321EB0f83dd5',
  timelock:'0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE',
  cm:'0x04C06323Fe3D53Deb7364c0055E1F68458Cc2570',
  guard:'0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B',
  oldGuard:'0x7bB7998b210cFfE10ca1e41f16341Abe53f76f3a',
  treasury:'0xa0DA53447C0f6C4987964d8463da7e6628B30f82',
  token:require('../evidence.json').addresses.votingWrapper,
  ve:'0x7e01A500805f8A52Fad229b3015AD130A332B7b3',
  daoProposer:'0x34471096285C2B59164E20c03f6977423a450039',
  whale:'0x063923C9b00Bd1eFb1EF5a89498538F5A1237a97',
  zero:ethers.constants.AddressZero
};
const activation='0x1ea31f9979e39a288a09aadabb1db1e4e76a124bb9f825cb07b4829bb46b0168';
const proposal15='3563000702947626407249966116394330391891319244018918786718598572660765109424';
const treasuryProposal='40206354484003228084362487350961959469393498496889094972132496370956127262976';
const abi=[
 'event ProposalCreated(uint256 proposalId,address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,uint256 startBlock,uint256 endBlock,string description)',
 'event ProposalQueued(uint256 proposalId,uint256 eta)', 'event ProposalExecuted(uint256 proposalId)', 'event ProposalCanceled(uint256 proposalId)',
 'event RoleGranted(bytes32 indexed role,address indexed account,address indexed sender)',
 'event RoleRevoked(bytes32 indexed role,address indexed account,address indexed sender)',
 'event MinDelayChange(uint256 oldDuration,uint256 newDuration)',
 'event ProposalThresholdSet(uint256 oldProposalThreshold,uint256 newProposalThreshold)',
 'event QuorumNumeratorUpdated(uint256 oldQuorumNumerator,uint256 newQuorumNumerator)',
 'event VotingDelaySet(uint256 oldVotingDelay,uint256 newVotingDelay)',
 'event VotingPeriodSet(uint256 oldVotingPeriod,uint256 newVotingPeriod)',
 'event GovernorDelayChange(uint256 newGovernorDelay)',
 'event TimelockChange(address oldTimelock,address newTimelock)',
 'event CallScheduled(bytes32 indexed id,uint256 indexed index,address target,uint256 value,bytes data,bytes32 predecessor,uint256 delay)',
 'event CallExecuted(bytes32 indexed id,uint256 indexed index,address target,uint256 value,bytes data)',
 'event Cancelled(bytes32 indexed id)'
];
const iface=new ethers.utils.Interface(abi);
const save=(name,v)=>fs.writeFileSync(path.join(out,name),JSON.stringify(v,null,2)+'\n');
function clean(v){if(ethers.BigNumber.isBigNumber(v))return v.toString();if(Array.isArray(v))return v.map(clean);return v;}
async function rpc(method,params,cache=true){
 if(!['eth_chainId','eth_blockNumber','eth_getBlockByNumber','eth_getLogs','eth_call','eth_getCode','eth_getStorageAt','eth_getTransactionReceipt','eth_getTransactionByHash'].includes(method))throw Error('Not read-only');
 const key=crypto.createHash('sha256').update(JSON.stringify([method,params])).digest('hex');
 const file=path.join(out,'rpc',key+'.json');
 if(cache&&fs.existsSync(file)){const old=JSON.parse(fs.readFileSync(file));if(!old.response.error)return old.response.result;}
 let lastError;
 for(const rpcEndpoint of [endpoint,'https://eth.drpc.org','https://1rpc.io/eth']){
  try {
   const response=await fetch(rpcEndpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params}),signal:AbortSignal.timeout(20000)});
   const value=await response.json();
   fs.writeFileSync(file,JSON.stringify({endpoint:rpcEndpoint,observedAt:new Date().toISOString(),method,params,response:value},null,2)+'\n');
   if(value.error)throw Error(JSON.stringify(value.error));return value.result;
  } catch(e){lastError=e;}
 }
 throw lastError;
}
const hex=n=>'0x'+n.toString(16);
async function call(address,signature,args,block){
 const i=new ethers.utils.Interface(['function '+signature]);const f=Object.values(i.functions)[0];
 try{return clean(i.decodeFunctionResult(f,await rpc('eth_call',[{to:address,data:i.encodeFunctionData(f,args)},hex(block)])))[0];}
 catch(e){return {error:e.message};}
}
async function firstBlockAt(timestamp,high){let low=0;while(low<high){const m=Math.floor((low+high)/2);const b=await rpc('eth_getBlockByNumber',[hex(m),false]);if(parseInt(b.timestamp,16)<timestamp)low=m+1;else high=m;}return low;}
async function main(){
 if(await rpc('eth_chainId',[])!=='0x1')throw Error('Wrong chain');
 const pinFile=path.join(out,'pin.json');
 let pin;
 if(fs.existsSync(pinFile))pin=JSON.parse(fs.readFileSync(pinFile));else{
  const latest=await rpc('eth_getBlockByNumber',['latest',false],false);
  pin={number:parseInt(latest.number,16),hash:latest.hash,timestamp:parseInt(latest.timestamp,16),observedAt:new Date().toISOString()};save('pin.json',pin);
 }
 console.log('Pinned block',pin.number,new Date(pin.timestamp*1000).toISOString());
 const receipt=await rpc('eth_getTransactionReceipt',[activation]);
 const tx=await rpc('eth_getTransactionByHash',[activation]);save('activation.json',{receipt,transaction:tx});
 const start=await firstBlockAt(Date.parse('2026-03-03T00:00:00Z')/1000,pin.number);
 const logs=[];
 fs.mkdirSync(path.join(out,'explorer'),{recursive:true});
 for(const address of [addr.governor,addr.oldGovernor,addr.timelock]){
  let next={};let page=0;
  do {
   const url='https://eth.blockscout.com/api/v2/addresses/'+address+'/logs?'+new URLSearchParams(next);
   const file=path.join(out,'explorer',address+'-'+page+'.json');
   let payload;
   if(fs.existsSync(file))payload=JSON.parse(fs.readFileSync(file)).response;
   else {payload=await (await fetch(url,{signal:AbortSignal.timeout(30000)})).json();fs.writeFileSync(file,JSON.stringify({url,observedAt:new Date().toISOString(),response:payload},null,2)+'\n');}
   if(!Array.isArray(payload.items))throw Error('Invalid explorer response');
   for(const item of payload.items){if(item.block_number>=start&&item.block_number<=pin.number)logs.push({address:item.address.hash,blockNumber:hex(item.block_number),transactionHash:item.transaction_hash,data:item.data,topics:item.topics.filter(Boolean),logIndex:hex(item.index)});}
   next=payload.next_page_params;
   if(payload.items.some(x=>x.block_number<start))next=null;
   page++;
  } while(next);
  console.log('Explorer pages',address,page);
 }
 const decoded=logs.flatMap(l=>{let p;try{p=iface.parseLog(l);}catch{return [];}return [{block:parseInt(l.blockNumber,16),logIndex:parseInt(l.logIndex,16),tx:l.transactionHash,address:l.address,event:p.name,args:Object.fromEntries(p.eventFragment.inputs.map((x,i)=>[x.name,clean(p.args[i])]))}];}).sort((a,b)=>a.block-b.block||a.logIndex-b.logIndex);
 save('events.json',decoded);
 const proposals=decoded.filter(e=>e.event==='ProposalCreated');
 for(const p of proposals){p.state=await call(p.address,'state(uint256) view returns(uint8)',[p.args.proposalId],pin.number);p.eta=await call(p.address,'proposalEta(uint256) view returns(uint256)',[p.args.proposalId],pin.number);}
 save('proposals.json',proposals);
 const receipts={};
 for(const hash of [...new Set(decoded.filter(e=>['ProposalCreated','ProposalExecuted','ProposalCanceled','RoleGranted','RoleRevoked'].includes(e.event)).map(e=>e.tx))])receipts[hash]=await rpc('eth_getTransactionReceipt',[hash]);
 save('event_receipts.json',receipts);
 const p15exec=decoded.find(e=>e.event==='ProposalExecuted'&&e.args.proposalId===proposal15);
 const blocks=[...new Set([parseInt(receipt.blockNumber,16)-1,parseInt(receipt.blockNumber,16),...(p15exec?[p15exec.block-1,p15exec.block]:[]),pin.number])];
 const candidates={...Object.fromEntries(Object.entries(addr).filter(([k])=>['governor','oldGovernor','firstGovernor','timelock','cm','guard','oldGuard','zero'].includes(k)))};
 for(const event of decoded.filter(e=>e.event==='RoleGranted'||e.event==='RoleRevoked'))candidates[event.args.account]=event.args.account;
 const snapshots=[];
 for(const block of blocks){
  const row={block,blockInfo:await rpc('eth_getBlockByNumber',[hex(block),false]),governors:{},roles:{},votes:{}};
  for(const name of ['governor','oldGovernor']){
   row.governors[name]={};
   for(const sig of ['token() view returns(address)','timelock() view returns(address)','proposalThreshold() view returns(uint256)','votingDelay() view returns(uint256)','votingPeriod() view returns(uint256)','governorDelay() view returns(uint256)','quorumNumerator() view returns(uint256)','quorumDenominator() view returns(uint256)','COUNTING_MODE() view returns(string)'])row.governors[name][sig.split('(')[0]]=await call(addr[name],sig,[],block);
  }
  row.minDelay=await call(addr.timelock,'getMinDelay() view returns(uint256)',[],block);
  row.treasuryOwner=await call(addr.treasury,'owner() view returns(address)',[],block);
  row.guardSlot=await rpc('eth_getStorageAt',[addr.cm,'0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8',hex(block)]);
  row.timelockModuleEnabled=await call(addr.cm,'isModuleEnabled(address) view returns(bool)',[addr.timelock],block);
  for(const [name,address] of Object.entries(candidates)){
   row.roles[name]={};
   await Promise.all(['TIMELOCK_ADMIN_ROLE','PROPOSER_ROLE','EXECUTOR_ROLE','CANCELLER_ROLE'].map(async role=>{row.roles[name][role]=await call(addr.timelock,'hasRole(bytes32,address) view returns(bool)',[ethers.utils.id(role),address],block);}));
  }
  const voters={daoProposer:addr.daoProposer,whale:addr.whale};
  const tp=proposals.find(p=>p.args.proposalId===treasuryProposal);if(tp)voters.treasuryProposer=tp.args.proposer;
  for(const [name,address] of Object.entries(voters))row.votes[name]={address,power:await call(addr.governor,'getVotes(address,uint256) view returns(uint256)',[address,block-1],block),lockedEnd:await call(addr.ve,'lockedEnd(address) view returns(uint256)',[address],block)};
  row.pastTotalSupply=await call(addr.token,'getPastTotalSupply(uint256) view returns(uint256)',[block-1],block);
  row.quorumPreviousBlock=await call(addr.governor,'quorum(uint256) view returns(uint256)',[block-1],block);
  snapshots.push(row);save('snapshots.json',snapshots);console.log('Snapshot collected',block);
 }
 save('manifest.json',{endpoint,pin,startBlock:start,addresses:addr,activation,proposal15,treasuryProposal,roleCoverage:'Named addresses plus all role-event accounts in collection window; not an enumeration of all pre-window role holders',sourceSnapshot:'93901ec315eb2b1d4683aab5615ef38b071228f8'});
}
module.exports={rpc,call,addr,out,save,iface,hex,proposal15,activation};
if(require.main===module)main().catch(e=>{console.error(e.message);process.exitCode=1;});
