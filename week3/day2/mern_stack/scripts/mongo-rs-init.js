// Wait for primary to be ready, then initialise the replica set
// This script runs inside the mongo1 container

const MAX_TRIES = 30;
let tries = 0;

function waitAndInit() {
  tries++;
  try {
    const status = rs.status();
    if (status.ok) {
      print('Replica set already initialised.');
      quit(0);
    }
  } catch (_) {
    // not yet initialised – fall through to rs.initiate()
  }

  try {
    const result = rs.initiate({
      _id: 'rs0',
      members: [
        { _id: 0, host: 'mongo1:27017', priority: 2 },
        { _id: 1, host: 'mongo2:27017', priority: 1 },  // internal port is 27017; host maps it to 27018
      ],
    });
    print('rs.initiate() result:', JSON.stringify(result));
  } catch (err) {
    print('rs.initiate() error (may retry):', err);
    if (tries < MAX_TRIES) {
      sleep(2000);
      waitAndInit();
    } else {
      print('Max retries reached. Exiting.');
      quit(1);
    }
  }
}

waitAndInit();
