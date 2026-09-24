// Offline reconstruction from recorded Timelock CallExecuted payloads.
// This is evidence of executed configuration calls, not a new live-state read.
const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');
const dir = path.join(__dirname, 'data');
const rows = JSON.parse(fs.readFileSync(path.join(dir, 'timeline.json')));
const guard = '0xc0b146d61e2a2c17e024477e01978d1fcf598c6b';
const iface = new ethers.utils.Interface([
  'function setTargetSelectorChainIds(address[] targets,bytes4[] selectors,uint256[] chains,bool[] statuses)',
  'function setBridgeMediatorL1BridgeParams(address[] l1,address[] verifiers,uint256[] chains,address[] l2)'
]);
const signatures = ['pause()', 'drainServiceSlashedFunds()', 'close(uint256[])', 'drain(address)',
  'setPauseState(uint8)', 'drain()', 'unpause()'];
const selectorNames = Object.fromEntries(signatures.map(s => [ethers.utils.id(s).slice(0,10), s]));
const permissions = new Map(), routes = new Map();
for (const r of rows) {
  if (r.event !== 'CallExecuted' || r.args.target.toLowerCase() !== guard) continue;
  let decoded;
  try { decoded = iface.parseTransaction({data:r.args.data}); } catch { continue; }
  const a=decoded.args;
  for(let j=0;j<a[0].length;j++) {
    const chainId=a[2][j].toString();
    const evidence={tx:r.tx, block:r.block, time:r.time};
    if(decoded.name==='setTargetSelectorChainIds') {
      permissions.set([a[0][j].toLowerCase(),a[1][j],chainId].join(':'),
        {target:a[0][j],selector:a[1][j],signature:selectorNames[a[1][j]]||'unknown',chainId,allowed:a[3][j],...evidence});
    } else {
      routes.set(a[0][j].toLowerCase(),{l1:a[0][j],verifier:a[1][j],chainId,l2:a[3][j],...evidence});
    }
  }
}
const output={method:'Latest value observed in collected successful Timelock configuration calls',
  limitations:['Not an exhaustive live-state read; does not validate L2 receiver ownership, bridge delivery or target behavior.'],
  routes:[...routes.values()],permissions:[...permissions.values()]};
fs.writeFileSync(path.join(dir,'guard_configuration_from_calls.json'),JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify({chains:output.routes.map(r=>r.chainId),l1:output.permissions.filter(p=>p.chainId==='1')},null,2));
