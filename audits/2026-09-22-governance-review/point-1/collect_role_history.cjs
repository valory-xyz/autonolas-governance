// Read-only history and state collector. Pinned to the existing review block.
const fs=require('fs'), path=require('path'), crypto=require('crypto');
const {ethers}=require('ethers');
const base=path.join(__dirname,'data'), out=path.join(base,'role-history');
fs.mkdirSync(path.join(out,'rpc'),{recursive:true});
const pin=JSON.parse(fs.readFileSync(path.join(base,'pin.json')));
const manifest=JSON.parse(fs.readFileSync(path.join(base,'manifest.json')));
const addr=manifest.addresses, hex=ethers.utils.hexValue;
const endpoints=['https://gateway.tenderly.co/public/mainnet','https://eth.drpc.org'];
const save=(name,value)=>fs.writeFileSync(path.join(out,name),JSON.stringify(value,null,2)+'\n');
async function rpc(method,params){
 const key=crypto.createHash('sha256').update(JSON.stringify([method,params])).digest('hex');
 const file=path.join(out,'rpc',key+'.json');
 if(fs.existsSync(file)){const c=JSON.parse(fs.readFileSync(file));if(!c.response.error)return c.response.result;}
 let last;
 for(const endpoint of endpoints){
  try{const response=await (await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params}),signal:AbortSignal.timeout(18000)})).json();
   fs.writeFileSync(file,JSON.stringify({endpoint,method,params,response,observedAt:new Date().toISOString()},null,2)+'\n');
   if(response.error)throw Error(JSON.stringify(response.error));return response.result;
  }catch(e){last=e;}
 }
 throw last;
}
const clean=v=>ethers.BigNumber.isBigNumber(v)?v.toString():Array.isArray(v)?v.map(clean):v;
async function call(to,sig,args=[]){const i=new ethers.utils.Interface(['function '+sig]);const f=Object.values(i.functions)[0];return clean(i.decodeFunctionResult(f,await rpc('eth_call',[{to,data:i.encodeFunctionData(f,args)},hex(pin.number)])));}
const events=new ethers.utils.Interface([
 'event RoleGranted(bytes32 indexed role,address indexed account,address indexed sender)',
 'event RoleRevoked(bytes32 indexed role,address indexed account,address indexed sender)',
 'event RoleAdminChanged(bytes32 indexed role,bytes32 indexed previousAdminRole,bytes32 indexed newAdminRole)'
]);
async function logs(from,to){
 try{return await rpc('eth_getLogs',[{address:addr.timelock,fromBlock:hex(from),toBlock:hex(to),topics:[Object.keys(events.events).map(s=>events.getEventTopic(s))]}]);}
 catch(e){if(to-from<10000||/fetch failed|ENOTFOUND|EPERM/.test(String(e)))throw e;const mid=Math.floor((from+to)/2);return [...await logs(from,mid),...await logs(mid+1,to)];}
}
async function main(){
 if(await rpc('eth_chainId',[])!=='0x1')throw Error('Wrong chain');
 const header=await rpc('eth_getBlockByNumber',[hex(pin.number),false]);
 if(header.hash.toLowerCase()!==pin.hash.toLowerCase())throw Error('Pin mismatch');
 console.log('Collecting Timelock role events from genesis through',pin.number);
 const raw=await logs(0,pin.number);save('logs.json',raw);
 const decoded=raw.map(l=>{const p=events.parseLog(l);return {block:parseInt(l.blockNumber,16),index:parseInt(l.logIndex,16),tx:l.transactionHash,event:p.name,args:Object.fromEntries(p.eventFragment.inputs.map((x,j)=>[x.name,clean(p.args[j])]))};}).sort((a,b)=>a.block-b.block||a.index-b.index);
 if(new Set(decoded.map(r=>r.tx+':'+r.index)).size!==decoded.length)throw Error('Duplicate logs');
 save('events.json',decoded);
 const receipts={};
 for(const tx of new Set(decoded.map(r=>r.tx))){
  const receipt=await rpc('eth_getTransactionReceipt',[tx]);if(receipt.status!=='0x1')throw Error('Failed receipt');
  for(const e of decoded.filter(r=>r.tx===tx)){const l=raw.find(x=>x.transactionHash===tx&&parseInt(x.logIndex,16)===e.index);if(!receipt.logs.some(x=>x.address.toLowerCase()===addr.timelock.toLowerCase()&&x.logIndex===l.logIndex&&x.data===l.data&&JSON.stringify(x.topics)===JSON.stringify(l.topics)))throw Error('Receipt mismatch');}
  receipts[tx]=receipt;
 }save('receipts.json',receipts);
 const members={}, allAccounts=new Set([ethers.constants.AddressZero,...Object.values(addr)]), admins={};
 for(const e of decoded){const a=e.args;members[a.role]??=new Set();if(a.account){allAccounts.add(a.account);if(e.event==='RoleGranted')members[a.role].add(a.account.toLowerCase());else members[a.role].delete(a.account.toLowerCase());}else admins[a.role]=a.newAdminRole;}
 const names={};
 for(const name of ['TIMELOCK_ADMIN_ROLE','PROPOSER_ROLE','EXECUTOR_ROLE','CANCELLER_ROLE','DEFAULT_ADMIN_ROLE']){const [role]=await call(addr.timelock,name+'() view returns(bytes32)');names[role]=name;members[role]??=new Set();}
 const roles=[];
 for(const [role, holders] of Object.entries(members)){
  const [admin]=await call(addr.timelock,'getRoleAdmin(bytes32) view returns(bytes32)',[role]);
  if(admin!==(admins[role]||ethers.constants.HashZero))throw Error('Admin replay mismatch');
  const checks=[];
  for(const account of [...new Set([...allAccounts].map(x=>x.toLowerCase()))]){const [actual]=await call(addr.timelock,'hasRole(bytes32,address) view returns(bool)',[role,account]);if(actual!==holders.has(account))throw Error('Membership mismatch '+account);checks.push({account,member:actual});}
  roles.push({role,name:names[role]||role,admin,adminName:names[admin]||admin,holders:[...holders],checks});
 }
 const firstBlock=decoded[0].block;
 const beforeCode=await rpc('eth_getCode',[addr.timelock,hex(firstBlock-1)]);
 const firstCode=await rpc('eth_getCode',[addr.timelock,hex(firstBlock)]);
 const guard={};
 for(const sig of ['paused() view returns(uint256)','governor() view returns(address)','governorCheckProposalId() view returns(uint256)'])guard[sig.split('(')[0]]=(await call(addr.guard,sig))[0];
 try{guard.heartbeatState=(await call(addr.governor,'state(uint256) view returns(uint8)',[guard.governorCheckProposalId]))[0];}catch(e){guard.heartbeatState={error:String(e)};}
 const modules=[];let cursor='0x0000000000000000000000000000000000000001';
 do{const [page,next]=await call(addr.cm,'getModulesPaginated(address,uint256) view returns(address[],address)',[cursor,100]);modules.push(...page);cursor=next;}while(cursor.toLowerCase()!=='0x0000000000000000000000000000000000000001');
 save('result.json',{pin,roleEventCount:decoded.length,firstRoleEventBlock:firstBlock,deploymentBoundary:{beforeCodeEmpty:beforeCode==='0x',firstCodeBytes:(firstCode.length-2)/2},roles,
   guard,cmModules:modules,minDelay:(await call(addr.timelock,'getMinDelay() view returns(uint256)'))[0],
   limitations:['Provider-backed reconstruction, not a cryptographic proof of log completeness. Receipts validate returned events.',
     'Historical role replay assumes deployed AccessControl membership mutations emit the standard events; source must be checked.',
     'State pinned to the review block; no transactions signed or broadcast.']});
 console.log(JSON.stringify({roleEventCount:decoded.length,firstBlock,roles:roles.map(({checks,...r})=>r),guard,cmModules:modules},null,2));
}
main().catch(e=>{console.error(e);process.exit(1)});
