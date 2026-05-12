const fs = require('fs');
const path = require('path');
try {
    const outfile = path.join(process.cwd(), 'node_test.txt');
    console.log('Writing to ' + outfile);
    fs.writeFileSync(outfile, 'Node is working!');
    console.log('Write success');
} catch (e) {
    console.error('Write failed: ' + e.message);
}
