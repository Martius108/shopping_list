import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteDoc, getDocFromServer, getDocs, query, where, collection, arrayUnion, arrayRemove, Timestamp, runTransaction, onSnapshot } from 'firebase/firestore';

let environment;
const ownerEmail = 'owner@example.test';
const guestEmail = 'guest@example.test';
const itemID = '00000000-0000-4000-8000-000000000001';
const session = (uid, email, verified = true) => environment.authenticatedContext(uid, {
  email, email_verified: verified
}).firestore();
const listData = () => ({ name: 'Groceries', ownerID: 'owner', ownerEmail,
  memberEmails: [ownerEmail], deleted: false, sharingReady: false });
const itemData = () => ({ name: 'Milk', amount: 1, isBought: false,
  createdAt: Timestamp.now(), updatedAt: Timestamp.now(), deletedAt: null });
const list = db => doc(db, 'shoppingLists', 'groceries');
const item = db => doc(db, 'shoppingLists', 'groceries', 'items', itemID);

before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-shopping-list',
    firestore: { host: '127.0.0.1', port: 8087, rules: await readFile(new URL('./firestore.rules', import.meta.url), 'utf8') } });
  await environment.clearFirestore();
});
after(async () => { await environment?.cleanup(); });

test('owner creates list and items; strangers and unverified accounts have no access', async () => {
  const owner = session('owner', ownerEmail);
  const stranger = session('stranger', 'stranger@example.test');
  const unverified = session('unverified', guestEmail, false);
  const anonymous = environment.unauthenticatedContext().firestore();
  await assertFails(setDoc(list(unverified), listData()));
  await assertFails(setDoc(list(stranger), listData()));
  await assertSucceeds(setDoc(list(owner), listData()));
  await assertSucceeds(setDoc(item(owner), itemData()));
  for (const db of [stranger, unverified, anonymous]) {
    await assertFails(getDocFromServer(list(db)));
    await assertFails(getDocFromServer(item(db)));
    await assertFails(setDoc(item(db), itemData()));
  }
});

test('invited, verified email can discover and edit list, but cannot take ownership or invite others', async () => {
  const owner = session('owner', ownerEmail);
  const guest = session('guest', guestEmail);
  await assertSucceeds(updateDoc(list(owner), { memberEmails: arrayUnion(guestEmail) }));
  await assertSucceeds(getDocFromServer(list(guest)));
  await assertSucceeds(getDocs(query(collection(guest, 'shoppingLists'), where('memberEmails', 'array-contains', guestEmail))));
  await assertFails(getDocs(collection(guest, 'shoppingLists')));
  await assertSucceeds(updateDoc(item(guest), { amount: 2, updatedAt: Timestamp.now() }));
  await assertFails(updateDoc(list(guest), { ownerID: 'guest' }));
  await assertFails(updateDoc(list(guest), { ownerEmail: guestEmail }));
  await assertFails(updateDoc(list(guest), { memberEmails: arrayUnion('outsider@example.test') }));
  await assertFails(updateDoc(list(guest), { memberEmails: [guestEmail] }));
  await assertFails(updateDoc(list(guest), { deleted: true }));
  await assertFails(deleteDoc(list(guest)));
  await assertFails(deleteDoc(item(guest)));
  await assertFails(getDocFromServer(list(session('not-verified', guestEmail, false))));
  await assertFails(getDocFromServer(list(session('wrong-email', 'other@example.test'))));
});

test('invalid item payloads are rejected and deletion tombstones are accepted', async () => {
  const guest = session('guest', guestEmail);
  await assertFails(updateDoc(item(guest), { amount: 0 }));
  await assertFails(updateDoc(item(guest), { amount: 1.5 }));
  await assertFails(updateDoc(item(guest), { name: '' }));
  await assertFails(updateDoc(item(guest), { isBought: 'yes' }));
  await assertFails(updateDoc(item(guest), { ownerID: 'guest' }));
  await assertSucceeds(updateDoc(item(guest), { deletedAt: Timestamp.now(), updatedAt: Timestamp.now() }));
});

test('revocation immediately blocks access; guests can leave only themselves', async () => {
  const owner = session('owner', ownerEmail);
  const guest = session('guest', guestEmail);
  await assertSucceeds(updateDoc(list(guest), { memberEmails: arrayRemove(guestEmail) }));
  await assertFails(getDocFromServer(item(guest)));
  await assertSucceeds(updateDoc(list(owner), { memberEmails: arrayUnion(guestEmail) }));
  await assertSucceeds(updateDoc(list(owner), { memberEmails: [ownerEmail] }));
  await assertFails(getDocFromServer(list(guest)));
  await assertFails(updateDoc(item(guest), { amount: 3 }));
});

test('deleted lists block their items and all undeclared paths remain closed', async () => {
  const owner = session('owner', ownerEmail);
  const guest = session('guest', guestEmail);
  await assertFails(deleteDoc(item(owner)));
  await assertSucceeds(updateDoc(list(owner), { memberEmails: arrayUnion(guestEmail) }));
  await assertSucceeds(updateDoc(list(owner), { deleted: true }));
  await assertFails(getDocFromServer(item(guest)));
  await assertFails(setDoc(item(owner), itemData()));
  await assertSucceeds(getDocFromServer(item(owner)));
  await assertFails(deleteDoc(item(guest)));
  await assertFails(setDoc(doc(owner, 'anythingElse', 'secret'), { public: true }));
  await assertFails(updateDoc(list(owner), { memberEmails: [] }));
  await assertSucceeds(deleteDoc(item(owner)));
  await assertSucceeds(deleteDoc(list(owner)));
});


test('first sharing uploads a new item transactionally and supports the same owner email on both apps', async () => {
  const owner = session('owner', ownerEmail);
  const reference = doc(owner, 'shoppingLists', 'first-sharing');
  const newItem = doc(reference, 'items', '00000000-0000-4000-8000-000000000002');
  // Before the root is committed, even its owner cannot read the item collection.
  await assertFails(getDocs(collection(reference, 'items')));
  await assertSucceeds(setDoc(reference, listData()));
  await assertSucceeds(getDocs(collection(reference, 'items')));
  await assertSucceeds(runTransaction(owner, async transaction => {
    const snapshot = await transaction.get(newItem);
    if (!snapshot.exists()) transaction.set(newItem, itemData());
  }));
  await assertSucceeds(updateDoc(reference, { memberEmails: arrayUnion(ownerEmail), sharingReady: true }));
  const confirmed = await getDocFromServer(reference);
  if (confirmed.data().sharingReady !== true) throw new Error('Sharing was not completed');
  const { sharingReady, ...retryData } = listData();
  await assertSucceeds(setDoc(reference, { ...retryData, memberEmails: arrayUnion(ownerEmail) }, { merge: true }));
  if ((await getDocFromServer(reference)).data().sharingReady !== true) throw new Error('Retry reset sharing completion');
});


test('sharing completion is owner controlled and preserves multiple participants', async () => {
  const owner = session('owner', ownerEmail);
  const guest = session('guest', guestEmail);
  const third = session('third', 'third@example.test');
  const reference = doc(owner, 'shoppingLists', 'completion');
  await assertFails(setDoc(reference, { ...listData(), sharingReady: true }));
  await assertFails(setDoc(reference, { ...listData(), sharingReady: 'yes' }));
  await assertSucceeds(setDoc(reference, listData()));
  await assertFails(getDocFromServer(doc(guest, reference.path)));
  await assertSucceeds(updateDoc(reference, { memberEmails: arrayUnion(guestEmail), sharingReady: true }));
  await assertFails(updateDoc(doc(guest, reference.path), { sharingReady: false }));
  await assertSucceeds(updateDoc(reference, { memberEmails: arrayUnion('third@example.test'), sharingReady: true }));
  await assertSucceeds(getDocFromServer(doc(guest, reference.path)));
  await assertSucceeds(getDocFromServer(doc(third, reference.path)));
  await assertSucceeds(updateDoc(doc(guest, reference.path), { memberEmails: arrayRemove(guestEmail) }));
  await assertSucceeds(updateDoc(reference, { memberEmails: [ownerEmail], sharingReady: false }));
  await assertFails(getDocFromServer(doc(third, reference.path)));
});


test('unsubscribe before deletion prevents a queued item sync from reading a removed parent', async () => {
  const owner = session('owner', ownerEmail);
  const reference = doc(owner, 'shoppingLists', 'listener-lifecycle');
  const row = doc(reference, 'items', itemID);
  await setDoc(reference, listData());
  await setDoc(row, itemData());
  let cancelledSyncs = 0, stopCancelled;
  await new Promise((resolve, reject) => {
    stopCancelled = onSnapshot(collection(reference, 'items'), { includeMetadataChanges: true }, snapshot => {
      if (!snapshot.metadata.fromCache && snapshot.size === 1) resolve();
      if (!snapshot.metadata.fromCache && snapshot.empty) cancelledSyncs++;
    }, reject);
  });
  let parentDeleted, controlReady, stopControl;
  const deletionFinished = new Promise(resolve => { parentDeleted = resolve; });
  const ready = new Promise(resolve => { controlReady = resolve; });
  const lateSync = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Expected queued sync to lose access')), 5000);
    const finish = error => { clearTimeout(timer); resolve(error); };
    stopControl = onSnapshot(collection(reference, 'items'), { includeMetadataChanges: true }, async snapshot => {
      if (!snapshot.metadata.fromCache && snapshot.size === 1) controlReady();
      if (!snapshot.metadata.fromCache && snapshot.empty) {
        await deletionFinished;
        try { await getDocFromServer(row); clearTimeout(timer); reject(new Error('Removed parent remained readable')); }
        catch (error) { finish(error); }
      }
    }, finish);
  });
  await ready;
  stopCancelled();
  try {
    await updateDoc(reference, { deleted: true });
    await deleteDoc(row);
    await deleteDoc(reference);
    parentDeleted();
    assert.equal((await lateSync).code, 'permission-denied');
    assert.equal(cancelledSyncs, 0);
  } finally { parentDeleted(); stopCancelled(); stopControl(); }
});


test('only the owner can rename a shared list and names remain validated', async () => {
  const owner = session('owner', ownerEmail);
  const guest = session('guest', guestEmail);
  const reference = doc(owner, 'shoppingLists', 'rename-list');
  await assertSucceeds(setDoc(reference, listData()));
  await assertSucceeds(updateDoc(reference, { memberEmails: arrayUnion(guestEmail), sharingReady: true }));
  await assertSucceeds(updateDoc(reference, { name: 'Weekend groceries' }));
  const guestReference = doc(guest, 'shoppingLists', 'rename-list');
  assert.equal((await getDocFromServer(guestReference)).data().name, 'Weekend groceries');
  await assertFails(updateDoc(guestReference, { name: 'Guest replacement' }));
  await assertFails(updateDoc(reference, { name: '' }));
  await assertFails(updateDoc(reference, { name: 'x'.repeat(1001) }));
  assert.equal((await getDocFromServer(reference)).data().name, 'Weekend groceries');
});
