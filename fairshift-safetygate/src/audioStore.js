const DB_NAME = 'fairshift-hazard-beacon-audio-v1';
const STORE = 'recordings';

function database() {
  return new Promise((resolve, reject) => {
    if (!('indexedDB' in window)) {
      reject(new Error('This browser cannot store recordings offline.'));
      return;
    }
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(STORE)) {
        request.result.createObjectStore(STORE);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error('Audio storage is unavailable.'));
  });
}

export async function saveAudio(id, blob) {
  const db = await database();
  try {
    await new Promise((resolve, reject) => {
      const transaction = db.transaction(STORE, 'readwrite');
      transaction.objectStore(STORE).put(blob, id);
      transaction.oncomplete = resolve;
      transaction.onerror = () => reject(transaction.error || new Error('Could not save audio.'));
      transaction.onabort = () => reject(transaction.error || new Error('Could not save audio.'));
    });
  } finally {
    db.close();
  }
}

export async function loadAudio(id) {
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const request = db.transaction(STORE, 'readonly').objectStore(STORE).get(id);
      request.onsuccess = () => resolve(request.result || null);
      request.onerror = () => reject(request.error || new Error('Could not load audio.'));
    });
  } finally {
    db.close();
  }
}

export async function deleteAudio(id) {
  const db = await database();
  try {
    await new Promise((resolve, reject) => {
      const transaction = db.transaction(STORE, 'readwrite');
      transaction.objectStore(STORE).delete(id);
      transaction.oncomplete = resolve;
      transaction.onerror = () => reject(transaction.error || new Error('Could not remove audio.'));
      transaction.onabort = () => reject(transaction.error || new Error('Could not remove audio.'));
    });
  } finally {
    db.close();
  }
}

export async function clearAudio() {
  const db = await database();
  try {
    await new Promise((resolve, reject) => {
      const transaction = db.transaction(STORE, 'readwrite');
      transaction.objectStore(STORE).clear();
      transaction.oncomplete = resolve;
      transaction.onerror = () => reject(transaction.error || new Error('Could not clear audio.'));
      transaction.onabort = () => reject(transaction.error || new Error('Could not clear audio.'));
    });
  } finally {
    db.close();
  }
}
