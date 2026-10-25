import json,urllib.request,urllib.error
base='http://127.0.0.1:9098/'
def request(path,body=None):
 data=None if body is None else json.dumps(body).encode()
 req=urllib.request.Request(base+path,data=data,headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=10) as response:return json.load(response)
def api(action,body):return request('identitytoolkit.googleapis.com/v1/accounts:'+action+'?key=fake-api-key',body)
def oob(kind,email):
 codes=request('emulator/v1/projects/demo-shopping-list/oobCodes')['oobCodes']
 return next(c['oobCode'] for c in reversed(codes) if c['requestType']==kind and c['email']==email)
email='owner@example.test';password='Strong-test-password-42!'
user=api('signUp',{'email':email,'password':password,'returnSecureToken':True})
uid=user['localId']
api('sendOobCode',{'requestType':'VERIFY_EMAIL','idToken':user['idToken']})
api('update',{'oobCode':oob('VERIFY_EMAIL',email)})
api('sendOobCode',{'requestType':'EMAIL_SIGNIN','email':email,'canHandleCodeInApp':True,'continueUrl':'https://shoppinglist-6c6f4.web.app/login/'})
code=oob('EMAIL_SIGNIN',email)
signed=api('signInWithEmailLink',{'email':email,'oobCode':code})
assert signed['localId']==uid
assert api('lookup',{'idToken':signed['idToken']})['users'][0]['emailVerified']
assert api('signInWithPassword',{'email':email,'password':password,'returnSecureToken':True})['localId']==uid
try:api('signInWithEmailLink',{'email':email,'oobCode':code});raise AssertionError('Reused code accepted')
except urllib.error.HTTPError as e:assert e.code==400
api('sendOobCode',{'requestType':'EMAIL_SIGNIN','email':email,'canHandleCodeInApp':True,'continueUrl':'https://shoppinglist-6c6f4.web.app/login/'})
try:api('signInWithEmailLink',{'email':'wrong@example.test','oobCode':oob('EMAIL_SIGNIN',email)});raise AssertionError('Wrong email accepted')
except urllib.error.HTTPError as e:assert e.code==400
new='new@example.test'
api('sendOobCode',{'requestType':'EMAIL_SIGNIN','email':new,'canHandleCodeInApp':True,'continueUrl':'https://shoppinglist-6c6f4.web.app/login/'})
created=api('signInWithEmailLink',{'email':new,'oobCode':oob('EMAIL_SIGNIN',new)})
assert api('lookup',{'idToken':created['idToken']})['users'][0]['emailVerified']
api('sendOobCode',{'requestType':'PASSWORD_RESET','email':new})
api('resetPassword',{'oobCode':oob('PASSWORD_RESET',new),'newPassword':password})
assert api('signInWithPassword',{'email':new,'password':password,'returnSecureToken':True})['localId']==created['localId']
print('Auth checks passed: same account/UID, verified email, old password retained, one-use link, wrong-email rejection, password setup for link-created accounts. No real emails sent.')
