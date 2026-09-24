// Offline verification: decode cached eth_call responses and compare to the pinned snapshot.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const crypto = require('crypto');
const { ethers } = require('ethers');
const dir = path.join(__dirname, 'data');
const read = name => JSON.parse(fs.readFileSync(path.join(dir, name), 'utf8'));
const manifest = read('manifest.json');
const pin = read('pin.json');
const snapshot = read('snapshots.json').find(s => s.block === pin.number);
assert(snapshot && snapshot.blockInfo.hash.toLowerCase() === pin.hash.toLowerCase());
const checks = [];
function verify(address, signature, args, expected) {
  const iface = new ethers.utils.Interface(['function ' + signature]);
  const fn = Object.values(iface.functions)[0];
  const params = [{to: address, data: iface.encodeFunctionData(fn, args)}, ethers.utils.hexValue(pin.number)];
  const key = crypto.createHash('sha256').update(JSON.stringify(['eth_call', params])).digest('hex');
  const file = 'rpc/' + key + '.json';
  const cached = read(file);
  assert.equal(cached.method, 'eth_call');
  assert.deepStrictEqual(cached.params, params);
  assert(!cached.response.error, file);
  const decoded = iface.decodeFunctionResult(fn, cached.response.result)[0];
  const value = ethers.BigNumber.isBigNumber(decoded) ? decoded.toString() : decoded;
  assert.deepStrictEqual(value, expected, signature);
  checks.push({address, signature, args, value, evidence: file});
}
for (const [name, roles] of Object.entries(snapshot.roles)) {
  const address = manifest.addresses[name] || name;
  for (const [role, expected] of Object.entries(roles)) {
    verify(manifest.addresses.timelock, 'hasRole(bytes32,address) view returns(bool)',
      [ethers.utils.id(role), address], expected);
  }
}
verify(manifest.addresses.timelock, 'getMinDelay() view returns(uint256)', [], snapshot.minDelay);
for (const name of ['governorDelay','proposalThreshold','votingDelay','votingPeriod','quorumNumerator','quorumDenominator']) {
  verify(manifest.addresses.governor, name + '() view returns(uint256)', [], snapshot.governors.governor[name]);
}
verify(manifest.addresses.governor, 'timelock() view returns(address)', [], snapshot.governors.governor.timelock);
const result = {block: pin.number, blockHash: pin.hash, checks,
  limitations: ['Offline verification of saved provider responses, not an independent RPC confirmation or cryptographic state proof.',
    'Known addresses and window-event accounts only; does not enumerate all role holders since deployment.',
    'eth_call requests used a block number; the corresponding saved header hash is checked against the pin.']};
fs.writeFileSync(path.join(dir, 'roles_verification.json'), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify({block:pin.number, verifiedCalls:checks.length, roles:snapshot.roles,
  timelockMinDelay:snapshot.minDelay, governor:snapshot.governors.governor}, null, 2));
