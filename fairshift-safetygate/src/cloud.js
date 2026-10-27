import {createClient} from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
export const cloudConfigured = Boolean(url && key);
export const cloud = cloudConfigured ? createClient(url, key) : null;
const bucket = 'hazard-evidence';

function fail(error) { if (error) throw new Error(error.message || 'Cloud request failed.'); }
function mimeOf(blob) { return (blob.type || 'application/octet-stream').split(';')[0]; }
function extension(mime) {
  return ({'image/jpeg':'jpg','image/png':'png','image/webp':'webp','audio/webm':'webm',
    'audio/mp4':'m4a','audio/ogg':'ogg'})[mime] || 'bin';
}
function dataBlob(dataUrl) {
  const [head,body] = dataUrl.split(',');
  const mime = head.match(/^data:([^;]+);base64$/)?.[1];
  if (!mime || !body) throw new Error('Invalid photo data.');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i=0;i<binary.length;i++) bytes[i]=binary.charCodeAt(i);
  return new Blob([bytes],{type:mime});
}

export async function cloudRole() {
  const {data,error}=await cloud.rpc('my_fairshift_role'); fail(error);
  return data;
}
export async function signInCloud(email,password) {
  const {data,error}=await cloud.auth.signInWithPassword({email,password}); fail(error);
  const role=await cloudRole();
  if (!['worker','supervisor','reviewer'].includes(role)) {
    await cloud.auth.signOut();
    throw new Error('This account has no FairShift role. Ask the project admin to assign one.');
  }
  return {user:data.user,role};
}
export async function signOutCloud() { const {error}=await cloud.auth.signOut(); fail(error); }

export async function signedMediaUrl(path) {
  if (!path) return '';
  const {data,error}=await cloud.storage.from(bucket).createSignedUrl(path,600);
  fail(error); return data.signedUrl;
}
export async function hydrateCloudRecord(row) {
  const source=row.payload || row;
  const record={...source,__cloudId:row.id || source.__cloudId};
  const paths=[source.imagePath,source.correctiveImagePath,...(source.protectionActions||[]).map(a=>a.imagePath)].filter(Boolean);
  const results=await Promise.allSettled(paths.map(signedMediaUrl));
  const signed=new Map(paths.map((path,index)=>[path,results[index].status==='fulfilled'?results[index].value:'']));
  record.image=signed.get(source.imagePath)||'';
  record.correctiveImage=signed.get(source.correctiveImagePath)||'';
  record.protectionActions=(source.protectionActions||[]).map(a=>({...a,image:signed.get(a.imagePath)||''}));
  return record;
}
export async function loadCloudReports() {
  const {data,error}=await cloud.from('hazards').select('id,payload').order('updated_at',{ascending:false});
  fail(error); return Promise.all((data||[]).map(hydrateCloudRecord));
}

async function upload(uid,id,kind,blob) {
  const mime=mimeOf(blob);
  if (!['image/jpeg','image/png','image/webp','audio/webm','audio/mp4','audio/ogg'].includes(mime))
    throw new Error('Unsupported evidence format.');
  const path=`${uid}/${id}/${kind}-${crypto.randomUUID()}.${extension(mime)}`;
  const {error}=await cloud.storage.from(bucket).upload(path,blob,{contentType:mime,upsert:false});
  fail(error); return {path,kind,mimeType:mime};
}
async function cleanup(media) {
  if (media.length) await cloud.storage.from(bucket).remove(media.map(item=>item.path));
}

export async function createCloudReport(record,form) {
  const {data:{user},error:authError}=await cloud.auth.getUser(); fail(authError);
  if (!user) throw new Error('Sign in before submitting.');
  const id=crypto.randomUUID(),media=[];
  let committed=false;
  try {
    if (form.image) { const item=await upload(user.id,id,'worker_photo',dataBlob(form.image)); media.push(item); record.imagePath=item.path; }
    const refs=[];
    for (const [step,kind] of [['description','worker_voice_description'],['warning','worker_voice_safety']]) {
      const clip=form[step+'Audio'];
      if (!clip) continue;
      const item=await upload(user.id,id,kind,clip.blob);
      item.duration=clip.duration; media.push(item);
      refs.push({id:item.path,step,duration:clip.duration,mimeType:item.mimeType,storagePath:item.path});
    }
    record.audioRefs=refs;
    const safe={...record,image:'',correctiveImage:''};
    const {data,error}=await cloud.rpc('create_fairshift_hazard',{p_id:id,p_record:safe,p_media:media});
    fail(error); committed=true; return hydrateCloudRecord({id,payload:data});
  } catch (error) { if(!committed)await cleanup(media); throw error; }
}

export async function actCloud(record,kind,data={},photoData='',photoKind='') {
  const media=[];
  let committed=false;
  try {
    if (photoData) {
      const {data:{user},error}=await cloud.auth.getUser(); fail(error);
      if (!user) throw new Error('Sign in before uploading evidence.');
      const item=await upload(user.id,record.__cloudId,photoKind,dataBlob(photoData));
      media.push(item);
      data[photoKind==='protection_photo'?'protectionImagePath':'correctiveImagePath']=item.path;
    }
    const {data:updated,error}=await cloud.rpc('act_on_fairshift_hazard',{
      p_id:record.__cloudId,p_expected:record.status,p_kind:kind,p_data:data,p_media:media});
    fail(error); committed=true; return hydrateCloudRecord({id:record.__cloudId,payload:updated});
  } catch (error) { if(!committed)await cleanup(media); throw error; }
}

export async function createCloudConcern(parent,id,trackingCode,note) {
  const uuid=crypto.randomUUID();
  const {data,error}=await cloud.rpc('create_fairshift_concern',{
    p_parent:parent.__cloudId,p_id:uuid,p_public_code:id,p_tracking_code:trackingCode,p_note:note});
  fail(error); return hydrateCloudRecord({id:uuid,payload:data});
}
