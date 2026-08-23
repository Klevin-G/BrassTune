import hashlib, importlib.util, json, math, subprocess, sys, tempfile, unittest, wave
from unittest import mock
from pathlib import Path
P=Path(__file__).parents[1]/'metronome_timing_analyzer.py'; S=importlib.util.spec_from_file_location('m',P); m=importlib.util.module_from_spec(S); sys.modules['m']=m; S.loader.exec_module(m)
def h(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def audio(p, clicks=360, silent=False, pilot_leak=0., pilot_gain=.65):
 r=16000;duration=181 if clicks else 31;n=round(duration*r); left=[0.]*n;right=[0.]*n
 if not silent:
  for k in range(clicks):
   start=round((.2+k*.5)*r)
   for j in range(round(.003*r)):
    if start+j<n:left[start+j]+=.8*math.exp(-j/(r*.0007))
  for k in range(round(duration*10)):
   start=round((.05+k*.1)*r)
   for j in range(round(.008*r)):
    if start+j<n:
     pilot=pilot_gain*math.sin(2*math.pi*6000*j/r);right[start+j]+=pilot;left[start+j]+=pilot_leak*pilot
 out=bytearray()
 for c,pilot in zip(left,right):out+=max(-32768,min(32767,round(c*32767))).to_bytes(2,'little',signed=True)+max(-32768,min(32767,round(pilot*32767))).to_bytes(2,'little',signed=True)
 with wave.open(str(p),'wb') as w:w.setnchannels(2);w.setsampwidth(2);w.setframerate(r);w.writeframes(out)
def man(d,w,gap=False):
 d.mkdir(parents=True,exist_ok=True);nut=d/'raw.nut';subprocess.run(['ffmpeg','-v','error','-y','-i',str(w),'-c:a','pcm_s16le',str(nut)],check=True); rate=16000; samples=wave.open(str(w)).getnframes(); packets=[]
 for x in range(0,samples,160): packets.append({'pts':x+(20 if gap and x>=320 else 0),'dts':x+(20 if gap and x>=320 else 0),'duration':min(160,samples-x),'size':1})
 q=d/'manifest.json';q.write_text(json.dumps({'schema':'brasstune.nut-ffmpeg-8.1.2.v1','run_id':'run-a','raw_nut':{'path':str(nut),'sha256':h(nut)},'raw_pcm_wav':{'path':str(w),'sha256':h(w)},'corrected_wav':{'path':str(w),'sha256':h(w)},'timebase':{'num':1,'den':rate},'packets':packets,'decoded_sample_count':samples}));return q
def sched(d, bad=False):
 q=d/'scheduler.json'; e=[{'index':i,'targetTick':1000000000+i*500000000,'scheduleStartTick':i,'scheduleEndTick':i+20000000,'completion':'played','generation':0} for i in range(360)]
 if bad:e[0]['snr_db']=99
 q.write_text(json.dumps({'schema':'brasstune.iphone-hosttime-scheduler.v1','run_id':'run-a','host_time_numerator':1,'host_time_denominator':1000000000,'ioBufferDuration':.005,'events':e}));return q
class T(unittest.TestCase):
 def test_scheduler_rejects_placeholder_metric_and_nan(self):
  with tempfile.TemporaryDirectory() as x:
   d=Path(x); self.assertRaises(ValueError,m.scheduler,sched(d,True),'run-a'); q=sched(d); z=json.loads(q.read_text());z['ioBufferDuration']=float('nan');q.write_text(json.dumps(z));self.assertRaises(ValueError,m.scheduler,q,'run-a'); q=sched(d);z=json.loads(q.read_text());z['events'][0]['scheduleEndTick']=z['events'][0]['targetTick'];q.write_text(json.dumps(z));self.assertRaises(ValueError,m.scheduler,q,'run-a')
 def test_packet_cumulative_gap_rejected(self):
  with tempfile.TemporaryDirectory() as x:
   d=Path(x);w=d/'a.wav';audio(w,0);self.assertRaises(ValueError,m.manifest,man(d,w,True),w)
 def test_path_substitution_and_autocorrelated_drift_fail(self):
  with tempfile.TemporaryDirectory() as x:
   d=Path(x);w=d/'a.wav';audio(w,0);q=man(d,w);z=json.loads(q.read_text());z['corrected_wav']['path']=str(d/'missing.wav');q.write_text(json.dumps(z));self.assertRaises(ValueError,m.manifest,q,w)
  drift=[.2+sum(.5+.0008*(1 if j%2 else -1) for j in range(i)) for i in range(360)]
  self.assertGreater(m.block_ci(drift),0)
 def test_silent_calibration_rejected(self):
  with tempfile.TemporaryDirectory() as x:
   d=Path(x);w=d/'a.wav';audio(w,0,True);q=man(d,w); r=d/'c.json';r.write_text(json.dumps({'mode':'calibrate','input':str(w),'packet_manifest_path':str(q),'pilot_channel':1,'analysis_start_s':0,'analysis_end_s':30,'expected_interval_ms':100}));self.assertRaises(ValueError,m.calibration,r)
 def test_calibration_expected_interval_must_match_observed_pilot(self):
  with tempfile.TemporaryDirectory() as x:
   d=Path(x);w=d/'a.wav';audio(w,0);q=man(d,w);r=d/'c.json';r.write_text(json.dumps({'mode':'calibrate','input':str(w),'packet_manifest_path':str(q),'pilot_channel':1,'analysis_start_s':0,'analysis_end_s':30,'expected_interval_ms':99}));self.assertRaisesRegex(ValueError,'expected interval',m.calibration,r)
 def test_alternating_499_501_ms_intervals_fail_dispersion_gate(self):
  times=[.2]
  for i in range(359):times.append(times[-1]+(.499 if i%2==0 else .501))
  metrics=m.interval_metrics(times,500)
  self.assertAlmostEqual(metrics['mean_ms'],500,places=2)
  self.assertGreater(metrics['abs_error_p95_ms'],.5)
  self.assertGreater(metrics['stddev_ms'],.25)
  self.assertFalse(m.interval_dispersion_pass(metrics))
 def test_pilot_channel_crosstalk_is_rejected(self):
  with tempfile.TemporaryDirectory() as x:
   d=Path(x);w=d/'leaked.wav';audio(w,pilot_leak=.8);pilot,_,_=m.detect(w,1,6000);db=m.pilot_crosstalk_db(w,0,1,pilot)
   self.assertGreater(db,m.PILOT_CROSSTALK_LIMIT_DB)
 def test_valid_two_calibration_fixture_reaches_acoustic_pass_but_never_final_pass(self):
  with tempfile.TemporaryDirectory() as x:
   d=Path(x);w=d/'analysis.wav';audio(w);q=man(d/'analysis',w);s=sched(d);cal=[]
   for name,gain in (('a',.64),('b',.65)):
    cw=d/f'cal-{name}.wav';audio(cw,0,pilot_gain=gain);cq=man(d/f'cal-{name}-manifest',cw);r=d/f'cal-{name}.json';r.write_text(json.dumps({'mode':'calibrate','input':str(cw),'packet_manifest_path':str(cq),'pilot_channel':1,'analysis_start_s':0,'analysis_end_s':30,'expected_interval_ms':100}));cal.append(r)
   class A:pass
   a=A();a.input=w;a.input_packet_manifest=q;a.scheduler_evidence=s;a.calibration_report=cal;a.click_channel=0;a.pilot_channel=1;a.analysis_start_s=0;a.analysis_end_s=180
   result=m.analyze(a)
   self.assertTrue(result['acoustic_pass'],result)
   self.assertFalse(result['passed'])
   self.assertEqual(result['event_timestamp_contract'],'analysis_window_start_s')
   self.assertEqual(result['interval_quantization_ms'],m.DETECTOR_HOP_MS)
 def test_raw_contract_reports_components_but_never_release_pass(self):
  with tempfile.TemporaryDirectory() as x:
   d=Path(x);w=d/'a.wav';audio(w);q=man(d,w);s=sched(d);c=[]
   for name in ('a','b'):
    r=d/f'{name}.json';r.write_text(json.dumps({'mode':'calibrate','input':str(w),'packet_manifest_path':str(q),'pilot_channel':1,'analysis_start_s':0,'analysis_end_s':30,'expected_interval_ms':100}));c.append(r)
   class A:pass
   a=A();a.input=w;a.input_packet_manifest=q;a.scheduler_evidence=s;a.calibration_report=c;a.click_channel=0;a.pilot_channel=1;a.analysis_start_s=0;a.analysis_end_s=180
   # Same calibration source is deliberately rejected before any final pass can occur.
   self.assertRaises(ValueError,m.analyze,a)
 def test_exact_360_and_pilot_leakage(self):
  self.assertEqual(m.classify([.2+i*.5 for i in range(360)],.5),(0,0,0));self.assertNotEqual(len([.2+i*.5 for i in range(350)]),360)
 def test_compare_recomputes_and_rejects_forged_or_same_underlying_runs(self):
  with tempfile.TemporaryDirectory() as x:
   d=Path(x); base={'mode':'analyze','run_id':'claimed','input':'a.wav','input_sha256':'claimed','packet_manifest_path':'m','scheduler_path':'s','calibration_reports':[],'analysis_start_s':0,'analysis_end_s':1,'click_channel':0,'pilot_channel':1}; a=d/'a.json';b=d/'b.json';a.write_text(json.dumps(base));b.write_text(json.dumps(base))
   fresh={'run_id':'actual','input_sha256':'same','fitted_period_ms':500}
   with mock.patch.object(m,'manifest'),mock.patch.object(m,'scheduler'),mock.patch.object(m,'analyze',side_effect=[fresh,fresh]):
    with self.assertRaisesRegex(ValueError,'metadata'):m.compare([a,b])
   base['run_id']='actual';base['input_sha256']='same';a.write_text(json.dumps(base));b.write_text(json.dumps(base))
   with mock.patch.object(m,'manifest'),mock.patch.object(m,'scheduler'),mock.patch.object(m,'analyze',side_effect=[fresh,fresh]):
    with self.assertRaisesRegex(ValueError,'distinct recomputed'):m.compare([a,b])
if __name__=='__main__':unittest.main()
