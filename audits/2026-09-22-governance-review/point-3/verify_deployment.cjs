// Read-only Ethereum/repository discovery. Raw responses are local/ignored.
// Reuses local/published pins; --refresh explicitly selects a new current snapshot.
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const {execFileSync} = require('child_process');
const {ethers} = require('ethers');
const root = path.resolve(__dirname, '../../..'), out = path.join(__dirname, 'data');
const refresh=process.argv.includes('--refresh');
fs.mkdirSync(path.join(out, 'responses'), {recursive:true});
const save = (name, value) => fs.writeFileSync(path.join(out, name), JSON.stringify(value, null, 2)+'\n');
const read = name => JSON.parse(fs.readFileSync(name));
const endpoints = ['https://gateway.tenderly.co/public/mainnet', 'https://eth.drpc.org'];
const key = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
async function get(url, cache=true) {
    const file = path.join(out, 'responses', key(url)+'.json');
    if (cache && fs.existsSync(file)) return read(file).response;
    const response = await fetch(url, {headers:{'User-Agent':'governance-review'}, signal:AbortSignal.timeout(30000)});
    if (!response.ok) throw Error(`${response.status}: ${url}`);
    const body = await response.json();
    fs.writeFileSync(file, JSON.stringify({url, collectedAt:new Date().toISOString(), response:body}, null, 2)+'\n');
    return body;
}
async function rpc(method, params, cache=true) {
    const file = path.join(out, 'responses', key([method, params])+'.json');
    if (cache && fs.existsSync(file) && !read(file).response.error) return read(file).response.result;
    let last;
    for (const endpoint of endpoints) {
        try {
            const response = await (await fetch(endpoint, {method:'POST', headers:{'Content-Type':'application/json'},
                body:JSON.stringify({jsonrpc:'2.0', id:1, method, params}), signal:AbortSignal.timeout(25000)})).json();
            fs.writeFileSync(file, JSON.stringify({endpoint, method, params, collectedAt:new Date().toISOString(), response}, null, 2)+'\n');
            if (response.error) throw Error(JSON.stringify(response.error));
            return response.result;
        } catch(e) {last=e;}
    }
    throw last;
}
const hex = ethers.utils.hexValue;
async function call(address, signature, block) {
    const abi = new ethers.utils.Interface(['function '+signature]), f=Object.values(abi.functions)[0];
    try {
        const result = await rpc('eth_call', [{to:address, data:abi.encodeFunctionData(f,[])}, hex(block)]);
        const value = abi.decodeFunctionResult(f, result)[0];
        return ethers.BigNumber.isBigNumber(value) ? value.toString() : value;
    } catch(e) {return {error:String(e)};}
}
async function readContract(address, methods, block) {
    const code=await rpc('eth_getCode', [address,hex(block)]);
    const result={address, runtimeBytes:(code.length-2)/2, runtimeHash:ethers.utils.keccak256(code)};
    for (const method of methods) result[method.split('(')[0]]=await call(address,method,block);
    return result;
}
async function source(address) {
    const body=await get('https://eth.blockscout.com/api/v2/smart-contracts/'+address);
    save('source-'+address.toLowerCase()+'.json', body);
    return body;
}
async function main() {
    if(await rpc('eth_chainId',[],false)!=='0x1') throw Error('Wrong chain');
    const review=read(path.join(__dirname,'../point-1/data/pin.json'));
    const pinFile=path.join(out,'current-pin.json');
    const publishedFile=path.join(__dirname,'deployment-evidence.json');
    if(!refresh&&!fs.existsSync(pinFile)&&fs.existsSync(publishedFile))save('current-pin.json',read(publishedFile).snapshots.at(-1).pin);
    if(refresh||!fs.existsSync(pinFile)) {
        const b=await rpc('eth_getBlockByNumber',['latest',false],false);
        save('current-pin.json',{number:parseInt(b.number,16),hash:b.hash,timestamp:parseInt(b.timestamp,16),collectedAt:new Date().toISOString()});
    }
    const current=read(pinFile);
    for(const pin of [review,current]) {
        const b=await rpc('eth_getBlockByNumber',[hex(pin.number),false]);
        if(b.hash.toLowerCase()!==pin.hash.toLowerCase()) throw Error('Pin mismatch');
    }
    console.log('Pins',review.number,current.number);
    const repositories={};
    for(const repo of ['autonolas-governance','autonolas-tokenomics']) {
        const published=!refresh&&fs.existsSync(publishedFile)?read(publishedFile).repositories[repo]:null;
        const commit=await get(`https://api.github.com/repos/valory-xyz/${repo}/commits/${published?.commit||'main'}`,!refresh);
        const globals=await get(`https://api.github.com/repos/valory-xyz/${repo}/contents/scripts/deployment/globals_mainnet.json?ref=${commit.sha}`);
        const config=JSON.parse(Buffer.from(globals.content,'base64').toString());
        repositories[repo]={commit:commit.sha,commitDate:commit.commit.committer.date,
            configPath:'scripts/deployment/globals_mainnet.json',
            addresses:Object.fromEntries(Object.entries(config).filter(([k])=>/voteWeighting|dispenser|tokenomicsProxy|treasuryAddress|veOLASAddress/i.test(k)))};
        save(repo+'-config.json',config);
    }
    save('repositories.json',repositories);
    const gov=read(path.join(root,'scripts/deployment/globals_mainnet.json'));
    const tokenomics=read(path.join(out,'autonolas-tokenomics-config.json'));
    const treasury=tokenomics.treasuryAddress;
    const snapshots=[];
    for(const pin of [review,current]) {
        const snapshot={pin};
        snapshot.treasury=await readContract(treasury,['owner() view returns(address)','tokenomics() view returns(address)','dispenser() view returns(address)'],pin.number);
        const tokenomicsAddress=snapshot.treasury.tokenomics;
        if(typeof tokenomicsAddress!=='string'||tokenomicsAddress===ethers.constants.AddressZero)throw Error('No active Tokenomics established');
        snapshot.tokenomics=await readContract(tokenomicsAddress,['owner() view returns(address)','dispenser() view returns(address)'],pin.number);
        const dispenser=snapshot.tokenomics.dispenser;
        if(typeof dispenser!=='string'||dispenser===ethers.constants.AddressZero)throw Error('No active Dispenser established');
        snapshot.dispenser=await readContract(dispenser,['owner() view returns(address)','tokenomics() view returns(address)',
            'treasury() view returns(address)','voteWeighting() view returns(address)','paused() view returns(uint8)'],pin.number);
        const weighting=snapshot.dispenser.voteWeighting;
        if(typeof weighting!=='string'||weighting===ethers.constants.AddressZero)throw Error('No authoritative VoteWeighting established');
        snapshot.voteWeighting=await readContract(weighting,['owner() view returns(address)','ve() view returns(address)',
            'dispenser() view returns(address)','getNumNominees() view returns(uint256)'],pin.number);
        const equal=(a,b)=>typeof a==='string'&&typeof b==='string'&&a.toLowerCase()===b.toLowerCase();
        snapshot.wiringChecks={
            treasuryAndTokenomicsDispenserAgree:equal(snapshot.treasury.dispenser,dispenser),
            dispenserTokenomicsMatches:equal(snapshot.dispenser.tokenomics,tokenomicsAddress),
            dispenserTreasuryMatches:equal(snapshot.dispenser.treasury,treasury),
            voteWeightingDispenserMatches:equal(snapshot.voteWeighting.dispenser,dispenser),
            veMatchesGovernanceConfiguration:equal(snapshot.voteWeighting.ve,gov.veOLASAddress),
            governanceOwnersAgree:[snapshot.tokenomics.owner,snapshot.dispenser.owner,snapshot.voteWeighting.owner].every(a=>equal(a,snapshot.treasury.owner))};
        if(Object.values(snapshot.wiringChecks).some(v=>!v))throw Error('Wiring mismatch; investigate before concluding activation');
        snapshots.push(snapshot);save('snapshots.json',snapshots);
        console.log('Wiring',pin.number,JSON.stringify(snapshot));
    }
    const search=await get('https://eth.blockscout.com/api/v2/search?q=VoteWeighting',!refresh);
    save('search.json',search);
    const candidates=new Set([gov.voteWeightingAddress,...snapshots.map(s=>s.voteWeighting.address),
        ...Object.values(repositories).map(r=>r.addresses.voteWeightingAddress).filter(Boolean)]);
    for(const item of search.items||[]) if(item.type==='contract'&&item.name==='VoteWeighting'&&item.address_hash)candidates.add(item.address_hash);
    const revised=fs.readFileSync(path.join(root,'contracts/VoteWeighting.sol'),'utf8');
    const baseline=execFileSync('git',['show','v1.2.5-post-external-audit:contracts/VoteWeighting.sol'],{cwd:root,encoding:'utf8'});
    const sourceResults=[];
    for(const address of new Set([...candidates].map(a=>a.toLowerCase()))) {
        try {
            const verified=await source(address);
            const code=await rpc('eth_getCode',[address,hex(current.number)]);
            const files=[{file_path:verified.file_path,source_code:verified.source_code},...(verified.additional_sources||[])];
            const vw=files.find(f=>(f.file_path||'').endsWith('VoteWeighting.sol'));
            sourceResults.push({address,name:verified.name,compiler:verified.compiler_version,
                optimizationRuns:verified.optimization_runs,evmVersion:verified.evm_version,
                verifiedSourceMatchesRevised:vw?.source_code===revised,
                verifiedSourceMatchesPreMayBaseline:vw?.source_code===baseline,
                verifiedSourceSha256:vw ? crypto.createHash('sha256').update(vw.source_code).digest('hex') : null,
                explorerRuntimeMatchesRpc:verified.deployed_bytecode?.toLowerCase()===code.toLowerCase(),
                runtimeHash:ethers.utils.keccak256(code),runtimeBytes:(code.length-2)/2,
                constructorInputs:verified.abi?.find(x=>x.type==='constructor')?.inputs,
                mutableDispenserSetter:verified.abi?.some(x=>x.type==='function'&&x.name==='changeDispenser'),
                dispenserDeclaredImmutable:/address\s+public\s+immutable\s+dispenser/.test(vw?.source_code||''),
                constructorArguments:verified.constructor_args});
        } catch(e) {sourceResults.push({address,error:String(e)});}
    }
    save('source-results.json',sourceResults);
    const active=snapshots[snapshots.length-1];
    const dispenserSource=await source(active.dispenser.address);
    const activeSource=await source(active.voteWeighting.address);
    const activityEvents=['CheckpointNominee','VoteForNominee','NomineeRelativeWeightWrite'];
    const eventInterface=new ethers.utils.Interface(activeSource.abi.filter(x=>x.type==='event'&&activityEvents.includes(x.name)));
    const recentLogs=await rpc('eth_getLogs',[{address:active.voteWeighting.address,
        fromBlock:hex(current.number-50000),toBlock:hex(current.number),
        topics:[activityEvents.map(name=>eventInterface.getEventTopic(name))]}]);
    save('recent-weight-logs.json',recentLogs);
    let activity={fromBlock:current.number-50000,toBlock:current.number,eventNames:activityEvents,matchingEvents:recentLogs.length,
        eventCounts:Object.fromEntries(activityEvents.map(name=>[name,recentLogs.filter(l=>eventInterface.parseLog(l).name===name).length]))};
    if(recentLogs.length) {
        const last=recentLogs[recentLogs.length-1];
        const transaction=await rpc('eth_getTransactionByHash',[last.transactionHash]);
        const receipt=await rpc('eth_getTransactionReceipt',[last.transactionHash]);
        if(receipt.status!=='0x1'||!receipt.logs.some(l=>l.address.toLowerCase()===last.address.toLowerCase()
            &&l.logIndex===last.logIndex&&l.data===last.data&&JSON.stringify(l.topics)===JSON.stringify(last.topics)))throw Error('Activity receipt mismatch');
        activity.last={event:eventInterface.parseLog(last).name,block:parseInt(last.blockNumber,16),transaction:last.transactionHash,
            transactionTarget:transaction.to,successful:true,receiptLogMatched:true};
    }
    save('activity.json',activity);
    const activeRow=sourceResults.find(s=>s.address===active.voteWeighting.address.toLowerCase());
    if(!activeRow||activeRow.error||!activeRow.explorerRuntimeMatchesRpc)throw Error('Active code identity not established');
    const dataHashes={};
    for(const file of ['repositories.json','snapshots.json','source-results.json','search.json','activity.json',
        'source-'+active.voteWeighting.address.toLowerCase()+'.json','source-'+active.dispenser.address.toLowerCase()+'.json']) {
        dataHashes[file]=crypto.createHash('sha256').update(fs.readFileSync(path.join(out,file))).digest('hex');
    }
    const summary={scope:'Ethereum canonical Treasury/Tokenomics/Dispenser configuration at two pinned blocks; discovery is bounded, not a proof of absence of every possible deployment',
        sourceSnapshot:execFileSync('git',['rev-parse','v1.3.0-pre-external-audit^{commit}'],{cwd:root,encoding:'utf8'}).trim(),
        revisedSourceSha256:crypto.createHash('sha256').update(revised).digest('hex'),repositories,snapshots,sourceResults,
        activeDispenserSource:{address:active.dispenser.address,name:dispenserSource.name,compiler:dispenserSource.compiler_version,
            sourceUrl:'https://eth.blockscout.com/api/v2/smart-contracts/'+active.dispenser.address,
            explorerRuntimeMatchesRpc:ethers.utils.keccak256(dispenserSource.deployed_bytecode)===active.dispenser.runtimeHash,
            pauseEnumExcerpt:dispenserSource.source_code?.match(/enum Pause\s*\{[^}]+\}/)?.[0]||null},
        discovery:{method:'Current mainnet configuration files from both repositories, current on-chain wiring, and Blockscout exact contract-name search',
            searchUrl:'https://eth.blockscout.com/api/v2/search?q=VoteWeighting',
            exactNameCandidates:(search.items||[]).filter(i=>i.type==='contract'&&i.name==='VoteWeighting').map(i=>i.address_hash),
            nextPage:search.next_page_params||null,unverifiedDeploymentsExcluded:true},
        conclusion:{historicalVersionActive:activeRow?.verifiedSourceMatchesPreMayBaseline===true&&activeRow?.explorerRuntimeMatchesRpc===true,
            revisedVersionActive:activeRow?.verifiedSourceMatchesRevised===true,
            revisedDeploymentFound:sourceResults.some(s=>s.verifiedSourceMatchesRevised===true),
            deploymentAbsenceProven:false},activity,localInputSha256:dataHashes};
    fs.writeFileSync(path.join(__dirname,'deployment-evidence.json'),JSON.stringify(summary,null,2)+'\n');
    console.log('Search items',JSON.stringify(search.items));
    console.log('Candidate sources',JSON.stringify(sourceResults,null,2));
    console.log('Activity',JSON.stringify(activity));
}
main().catch(e=>{console.error(e);process.exitCode=1;});
