import React, {useEffect, useRef, useState} from 'react';
import {Mic,Square,Trash2,Volume2} from 'lucide-react';
import {loadAudio} from './audioStore';
import {signedMediaUrl} from './cloud';

const MAX_SECONDS = 60;
const seconds = value => Math.floor(value / 60) + ':' + String(value % 60).padStart(2, '0');

export function SpeakButton({text, lang, compact = false, label}) {
  const [message, setMessage] = useState('');
  async function speak(event) {
    event.preventDefault();
    event.stopPropagation();
    setMessage('');
    if (!('speechSynthesis' in window)) {
      setMessage(lang === 'ta' ? 'இந்தச் சாதனத்தில் ஒலி வாசிப்பு இல்லை.' : 'Speech playback is unavailable on this device.');
      return;
    }
    let voices = speechSynthesis.getVoices();
    if (!voices.length && typeof speechSynthesis.addEventListener === 'function') {
      await new Promise(resolve => {
        const timeout = setTimeout(resolve, 1200);
        speechSynthesis.addEventListener('voiceschanged', () => {
          clearTimeout(timeout);
          resolve();
        }, {once: true});
      });
      voices = speechSynthesis.getVoices();
    }
    const matching = voices.find(voice => voice.lang?.toLowerCase().startsWith(lang === 'ta' ? 'ta' : 'en'));
    if (lang === 'ta' && !matching) {
      setMessage('இந்தச் சாதனத்தில் தமிழ் குரல் இல்லை. உரை அல்லது உதவியுடன் புகாரளிக்கவும்.');
      return;
    }
    speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = lang === 'ta' ? 'ta-IN' : 'en-US';
    if (matching) utterance.voice = matching;
    utterance.rate = 0.85;
    utterance.onerror = () => setMessage(lang === 'ta' ? 'தமிழ் ஒலி இயங்கவில்லை.' : 'Speech playback failed.');
    speechSynthesis.speak(utterance);
  }
  return <span className={'speakWrap ' + (compact ? 'compact' : '')}><button type="button" className="speakButton" onClick={speak} aria-label={label || (lang === 'ta' ? 'கேளுங்கள்' : 'Listen')} title={label || (lang === 'ta' ? 'கேளுங்கள்' : 'Listen')}><Volume2 size={18}/>{!compact && <span>{lang === 'ta' ? 'கேளுங்கள்' : 'Listen'}</span>}</button>{message && <small className="speechMessage" role="status">{message}</small>}</span>;
}

export function VoiceRecorder({label, lang, clip, onChange, anonymous = false, cloudMode = false}) {
  const [recording, setRecording] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [error, setError] = useState('');
  const recorder = useRef(null);
  const stream = useRef(null);
  const timer = useRef(null);
  const started = useRef(0);
  const chunks = useRef([]);
  useEffect(() => () => {
    clearInterval(timer.current);
    if (recorder.current?.state === 'recording') recorder.current.stop();
    stream.current?.getTracks().forEach(track => track.stop());
  }, []);
  useEffect(() => () => {
    if (clip?.url) URL.revokeObjectURL(clip.url);
  }, [clip?.url]);
  async function start() {
    setError('');
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
      setError(lang === 'ta' ? 'இந்த உலாவியில் ஒலிப்பதிவு இல்லை.' : 'Recording is unavailable in this browser.');
      return;
    }
    try {
      // The permission prompt occurs only here, after a worker taps Record.
      const microphone = await navigator.mediaDevices.getUserMedia({audio: {channelCount: 1, echoCancellation: true, noiseSuppression: true}});
      stream.current = microphone;
      const mimeType = ['audio/webm;codecs=opus','audio/mp4','audio/webm'].find(type => typeof MediaRecorder.isTypeSupported === 'function' && MediaRecorder.isTypeSupported(type));
      const options = mimeType ? {mimeType, audioBitsPerSecond: 24000} : {audioBitsPerSecond: 24000};
      const mediaRecorder = new MediaRecorder(microphone, options);
      recorder.current = mediaRecorder;
      chunks.current = [];
      mediaRecorder.ondataavailable = event => { if (event.data.size) chunks.current.push(event.data); };
      mediaRecorder.onstop = () => {
        clearInterval(timer.current);
        microphone.getTracks().forEach(track => track.stop());
        stream.current = null;
        setRecording(false);
        const duration = Math.min(MAX_SECONDS, Math.max(1, Math.ceil((Date.now() - started.current) / 1000)));
        const blob = new Blob(chunks.current, {type: mediaRecorder.mimeType || 'audio/webm'});
        if (blob.size) onChange({blob, url: URL.createObjectURL(blob), duration, mimeType: blob.type});
        else setError(lang === 'ta' ? 'ஒலி பதிவாகவில்லை. மீண்டும் முயலவும்.' : 'No audio was captured. Please try again.');
      };
      mediaRecorder.onerror = () => setError(lang === 'ta' ? 'ஒலிப்பதிவு தோல்வியடைந்தது.' : 'Recording failed.');
      started.current = Date.now();
      setElapsed(0);
      mediaRecorder.start(1000);
      setRecording(true);
      timer.current = setInterval(() => {
        const value = Math.floor((Date.now() - started.current) / 1000);
        setElapsed(Math.min(MAX_SECONDS, value));
        if (value >= MAX_SECONDS && recorder.current?.state === 'recording') recorder.current.stop();
      }, 250);
    } catch (cause) {
      stream.current?.getTracks().forEach(track => track.stop());
      stream.current = null;
      setError(cause?.name === 'NotAllowedError'
        ? (lang === 'ta' ? 'மைக்ரோஃபோன் அனுமதி மறுக்கப்பட்டது. உரை அல்லது தேர்வுகளைப் பயன்படுத்தலாம்.' : 'Microphone permission was denied. You can use text or the answer buttons.')
        : (lang === 'ta' ? 'மைக்ரோஃபோன் கிடைக்கவில்லை. உரை அல்லது தேர்வுகளைப் பயன்படுத்தலாம்.' : 'Microphone unavailable. You can use text or the answer buttons.'));
    }
  }
  function stop() {
    if (recorder.current?.state === 'recording') recorder.current.stop();
  }
  return <div className={'voiceRecorder ' + (recording ? 'isRecording' : '')}>
    <div className="voiceHeading"><Mic size={19}/><strong>{label}</strong></div>
    {anonymous && <p className="voicePrivacy">{cloudMode
      ? (lang === 'ta' ? 'உங்கள் குரல் உங்கள் அடையாளத்தை வெளிப்படுத்தலாம். ஒலி தனிப்பட்ட சேமிப்பகத்தில் பதிவேற்றப்படும்.' : 'Your voice may identify you. Audio will be uploaded to private cloud storage.')
      : (lang === 'ta' ? 'உங்கள் குரல் அடையாளத்தை வெளிப்படுத்தலாம். இந்தச் சாதனத்தில் ஒலி சேமிக்கப்படும். உரை அல்லது தேர்வுகளையும் பயன்படுத்தலாம்.' : 'Your voice may identify you. Audio stays on this device. You can use text or answer buttons instead.')}</p>}
    {recording ? <div className="recordingRow"><span className="recordingStatus" role="status"><i/>{lang === 'ta' ? 'பதிவு நடக்கிறது' : 'Recording'} · {seconds(elapsed)} / 1:00</span><button type="button" className="recordButton stop" onClick={stop}><Square size={20}/>{lang === 'ta' ? 'நிறுத்து' : 'Stop'}</button></div>
      : <button type="button" className="recordButton" onClick={start}><Mic size={22}/>{lang === 'ta' ? 'பதிவைத் தொடங்கு' : 'Start recording'}</button>}
    {clip && !recording && <div className="recordingPreview"><span>{lang === 'ta' ? 'உங்கள் பதிவு' : 'Your recording'} · {seconds(clip.duration)}</span><audio controls preload="metadata" src={clip.url} aria-label={label}/><button type="button" className="deleteRecording" onClick={() => onChange(null)}><Trash2 size={17}/>{lang === 'ta' ? 'நீக்கு' : 'Delete and re-record'}</button></div>}
    {error && <p className="error" role="alert">{error}</p>}
  </div>;
}

export function AudioEvidence({reference, label, lang}) {
  const [url, setUrl] = useState('');
  const [error, setError] = useState('');
  useEffect(() => {
    let active = true;
    let objectUrl = '';
    (reference.storagePath ? signedMediaUrl(reference.storagePath) : loadAudio(reference.id)).then(result => {
      if (!active) return;
      if (!result) { setError(lang === 'ta' ? 'ஒலிப்பதிவு கிடைக்கவில்லை.' : 'Recording unavailable.'); return; }
      if (reference.storagePath) setUrl(result);
      else { objectUrl = URL.createObjectURL(result); setUrl(objectUrl); }
    }).catch(() => { if (active) setError(lang === 'ta' ? 'ஒலிப்பதிவைத் திறக்க முடியவில்லை.' : 'Could not load recording.'); });
    return () => { active = false; if (objectUrl) URL.revokeObjectURL(objectUrl); };
  }, [reference.id, lang]);
  return <div className="audioEvidence"><div><Volume2 size={17}/><strong>{label}</strong><span>{seconds(reference.duration)}</span></div>{url ? <audio controls preload="metadata" src={url} aria-label={label}/> : <small role="status">{error || (lang === 'ta' ? 'ஒலியைத் திறக்கிறது…' : 'Loading audio…')}</small>}</div>;
}
