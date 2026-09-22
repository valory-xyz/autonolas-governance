const fs=require('fs'),path=require('path'),{ethers}=require('ethers');
const {rpc,call,addr,out,save,hex}=require('./collect_chain.cjs');
async function main(){
 const pin=JSON.parse(fs.readFileSync(path.join(out,'pin.json')));
 const records={block:pin.number,guardChecks:{},code:{},proposals:{}};
 for(const signature of ['updateDelay(uint256)','grantRole(bytes32,address)','setProposalThreshold(uint256)','updateGovernorDelay(uint256)']){
  const target=signature.startsWith('updateDelay')||signature.startsWith('grantRole')?addr.timelock:addr.governor;
  records.guardChecks[signature]=await call(addr.guard,'getTargetSelectorChainId(address,bytes4,uint256) view returns(bool)',[target,ethers.utils.id(signature).slice(0,10),1],pin.number);
 }
 for(const name of ['governor','oldGovernor','timelock']){
  const address=addr[name];const file=path.join(out,'explorer','verified-'+name+'.json');
  let details;
  if(fs.existsSync(file))details=JSON.parse(fs.readFileSync(file)).response;
  else {const url='https://eth.blockscout.com/api/v2/smart-contracts/'+address;details=await(await fetch(url,{signal:AbortSignal.timeout(30000)})).json();fs.writeFileSync(file,JSON.stringify({url,observedAt:new Date().toISOString(),response:details},null,2)+'\n');}
  const code=await rpc('eth_getCode',[address,hex(pin.number)]);
  records.code[name]={address,bytes:(code.length-2)/2,hash:ethers.utils.keccak256(code),compiler:details.compiler_version,optimization:details.optimization_enabled,runs:details.optimization_runs,verifiedAt:details.verified_at,evmVersion:details.evm_version,constructorArgs:details.constructor_args};
  fs.writeFileSync(path.join(out,name+'-runtime.hex'),code+'\n');
  if(details.file_path&&details.source_code){
   const sources=[{file_path:details.file_path,source_code:details.source_code},...(details.additional_sources||[])];
   records.code[name].sourceChecks=sources.filter(s=>s.file_path.startsWith('contracts/')).map(s=>({path:s.file_path,equalsCheckout:fs.existsSync(s.file_path)?fs.readFileSync(s.file_path,'utf8')===s.source_code:null}));
  }
 }
 const ps=JSON.parse(fs.readFileSync(path.join(out,'proposals.json')));
 for(const p of ps.filter(p=>p.args.description.includes('Treasury')||p.args.description.startsWith('Owner migration')||p.args.description.startsWith('Raise the Olas'))){
  const id=p.args.proposalId;
  records.proposals[id]={snapshot:p.args.startBlock,deadline:p.args.endBlock,proposer:p.args.proposer,quorumAtSnapshot:await call(p.address,'quorum(uint256) view returns(uint256)',[p.args.startBlock],pin.number)};
  const govIface=new ethers.utils.Interface(['function proposals(uint256) view returns(uint256 id,address proposer,uint256 eta,uint256 startBlock,uint256 endBlock,uint256 forVotes,uint256 againstVotes,uint256 abstainVotes,bool canceled,bool executed)']);
  const raw=await rpc('eth_call',[{to:p.address,data:govIface.encodeFunctionData('proposals',[id])},hex(pin.number)]);
  const decoded=govIface.decodeFunctionResult('proposals',raw);
  records.proposals[id].bravo=Object.fromEntries(govIface.getFunction('proposals').outputs.map((x,i)=>[x.name,ethers.BigNumber.isBigNumber(decoded[i])?decoded[i].toString():decoded[i]]));
 }
 save('enrichment.json',records);
 console.log(JSON.stringify(records,null,2));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
