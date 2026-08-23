#!/usr/bin/env python3
"""Fail-closed consumer metronome cadence QA (never a final trace-release pass).

Input contract: raw NUT + raw PCM WAV + corrected PCM WAV are SHA256-bound by a
`brasstune.nut-ffmpeg-8.1.2.v1` packet manifest. Scheduler evidence contains
only raw host-time facts. This program recomputes every cadence/audio metric.
It intentionally leaves `passed=false`: an xctrace directory needs a dedicated
export parser before render-deadline/trace claims can be made.

`ffprobe` validates that the raw artifact is a NUT container, but this tool does
not yet derive packet rows from ffprobe output. The manifest packet rows are
therefore treated as a fail-closed evidence contract rather than independent
packet-proof.
"""
from __future__ import annotations
import argparse, hashlib, json, math, random, statistics, subprocess, sys, wave
from pathlib import Path

EXPECTED_CLICK_INTERVAL_MS=500.0
CALIBRATION_EXPECTED_TOLERANCE_MS=0.5
DETECTOR_HOP_MS=1.0
DETECTOR_WINDOW_MS=5.0
# Event timestamps are detector-window starts, quantized to DETECTOR_HOP_MS.
# All SNR and pilot-energy measurements use that exact same 5 ms window.
CLICK_INTERVAL_P95_ABS_ERROR_LIMIT_MS=1.0
CLICK_INTERVAL_MAX_ABS_ERROR_LIMIT_MS=1.5
CLICK_INTERVAL_STDDEV_LIMIT_MS=0.5
CLICK_INTERVAL_MAD_LIMIT_MS=0.5
PILOT_CROSSTALK_LIMIT_DB=-30.0

def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1<<20),b''): h.update(b)
    return h.hexdigest()
def pct(a,p):
    a=sorted(a); x=(len(a)-1)*p; i=int(x); j=min(i+1,len(a)-1); return a[i]+(a[j]-a[i])*(x-i)
def wav(path,ch=0):
    with wave.open(str(path),'rb') as w:
        if w.getcomptype()!='NONE' or w.getsampwidth()!=2: raise ValueError('WAV must be 16-bit PCM')
        n,r=w.getnchannels(),w.getframerate(); raw=w.readframes(w.getnframes())
    if not 0<=ch<n: raise ValueError('channel out of range')
    s=[int.from_bytes(raw[i+2*ch:i+2*ch+2],'little',signed=True)/32768 for i in range(0,len(raw),2*n)]
    return r,s,any(abs(x)>=.999 for x in s)
def goertzel(x,r,f):
    c=2*math.cos(2*math.pi*f/r); a=b=0.
    for y in x: a,b=y+c*a-b,a
    return max(0.,a*a+b*b-c*a*b)/max(1,len(x))
def detect(path,ch,freq,hop_ms=DETECTOR_HOP_MS,window_ms=DETECTOR_WINDOW_MS):
    r,s,clip=wav(path,ch); h=max(1,round(r*hop_ms/1000)); n=max(16,round(r*window_ms/1000))
    e=[goertzel(s[i:i+n],r,freq) for i in range(0,len(s)-n+1,h)]
    lo,hi=pct(e,.1),pct(e,.99)
    if hi-lo<=1e-15: return [],clip,r
    t=lo+.35*(hi-lo); radius=3; candidates=[i for i in range(radius,len(e)-radius) if e[i]>=t and e[i]==max(e[i-radius:i+radius+1])]
    # Refractory is measured-only; no expected-grid snapping.
    chosen=[]
    for i in sorted(candidates,key=lambda q:e[q],reverse=True):
        if all(abs(i-j)>=20 for j in chosen): chosen.append(i)
    # The canonical timestamp is the start of the Goertzel analysis window,
    # not an inferred acoustic onset. This keeps cadence intervals quantized
    # to the documented 1 ms detector hop and lets SNR reuse the exact window.
    return sorted(i*h/r for i in chosen),clip,r
def hash_bound(path, expected):
    if not Path(path).is_file() or sha(path)!=expected: raise ValueError('artifact hash/path binding failed')
def manifest(path, corrected):
    d=json.loads(Path(path).read_text())
    if d.get('schema')!='brasstune.nut-ffmpeg-8.1.2.v1': raise ValueError('invalid NUT/FFmpeg manifest schema')
    for key in ('raw_nut','raw_pcm_wav','corrected_wav','timebase','packets','decoded_sample_count','run_id'):
        if key not in d: raise ValueError('manifest missing '+key)
    for item in ('raw_nut','raw_pcm_wav','corrected_wav'): hash_bound(d[item]['path'],d[item]['sha256'])
    try:
        probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-of','json',d['raw_nut']['path']],text=True,stderr=subprocess.DEVNULL))
        if 'nut' not in probe.get('format',{}).get('format_name','').split(','): raise ValueError('raw artifact is not NUT')
    except (OSError,subprocess.CalledProcessError,json.JSONDecodeError): raise ValueError('raw NUT ffprobe 8.1.2 validation unavailable/failed')
    if Path(d['corrected_wav']['path']).resolve()!=Path(corrected).resolve(): raise ValueError('manifest corrected WAV path substitution')
    tb=d['timebase']
    if type(tb.get('num')) is not int or type(tb.get('den')) is not int: raise ValueError('timebase requires exact Python integer facts')
    num,den=tb['num'],tb['den']
    if num<=0 or den<=0: raise ValueError('invalid rational timebase')
    rate,s,_=wav(corrected); raw_rate,raw_s,_=wav(d['raw_pcm_wav']['path'])
    if raw_rate!=rate or num/den>1/rate: raise ValueError('timebase/sample consistency failed')
    p=d['packets']
    if not p: raise ValueError('empty packet manifest')
    last=-1; last_end=-1; total=0
    for x in p:
        if any(type(x.get(key)) is not int for key in ('pts','dts','duration','size')): raise ValueError('packet fields require exact Python integers')
        q=(x['pts'],x['dts'],x['duration'],x['size'])
        if q[0]!=q[1] or q[2]<=0 or q[3]<0 or q[0]<=last: raise ValueError('invalid/nonmonotonic PTS/DTS packet')
        if last>=0 and abs(q[0]-last_end)*num/den>.0005: raise ValueError('packet gap/overlap exceeds .5ms')
        last=q[0]; last_end=q[0]+q[2]; total+=q[2]
    if type(d['decoded_sample_count']) is not int or abs(total*num/den-len(s)/rate)>1/rate or d['decoded_sample_count']!=len(s): raise ValueError('packet duration/sample count mismatch')
    if any(x['size']==0 for x in p): raise ValueError('packet size/sample consistency unavailable')
    if len(raw_s)!=len(s): raise ValueError('raw/corrected decoded sample count mismatch')
    return d
def scheduler(path,run_id):
    d=json.loads(Path(path).read_text())
    if d.get('schema')!='brasstune.iphone-hosttime-scheduler.v1' or d.get('run_id')!=run_id: raise ValueError('scheduler schema/run binding failed')
    if type(d['host_time_numerator']) is not int or type(d['host_time_denominator']) is not int or type(d['ioBufferDuration']) not in (int,float): raise ValueError('host-time facts must be typed integers/numbers')
    num,den=d['host_time_numerator'],d['host_time_denominator']; io=float(d['ioBufferDuration'])
    if num<=0 or den<=0 or not math.isfinite(io) or io<=0: raise ValueError('invalid host-time/io facts')
    e=d.get('events'); tick=num/den
    if not isinstance(e,list) or len(e)!=360: raise ValueError('requires exactly 360 scheduler rows')
    targets=[]
    for i,x in enumerate(e):
        if set(x)!= {'index','targetTick','scheduleStartTick','scheduleEndTick','completion','generation'}: raise ValueError('scheduler contains non-raw/unknown fields')
        vals=[x['index'],x['targetTick'],x['scheduleStartTick'],x['scheduleEndTick'],x['generation']]
        if any(type(v) is not int for v in vals) or x['index']!=i or x['targetTick']<0 or x['scheduleStartTick']<0 or x['scheduleEndTick']<x['scheduleStartTick'] or x['generation']<0 or x['completion']!='played': raise ValueError('invalid scheduler row')
        if (x['targetTick']-x['scheduleEndTick'])*tick < max(.010,2*io): raise ValueError('late/insufficient schedule completion lead')
        targets.append(x['targetTick'])
    if any(b<=a or abs((b-a)*tick-.5)>tick for a,b in zip(targets,targets[1:])): raise ValueError('scheduler cadence invalid')
    return d
def classify(times,T):
    dup=miss=amb=0
    for a,b in zip(times,times[1:]):
        q=(b-a)/T
        if q<.5: dup+=1
        elif q>1.5:
            k=round(q)
            if abs(q-k)<=.2: miss+=k-1
            else: amb+=1
    return dup,miss,amb
def fit(times):
    x=list(range(len(times))); xm=statistics.mean(x); ym=statistics.mean(times); slope=sum((a-xm)*(b-ym) for a,b in zip(x,times))/sum((a-xm)**2 for a in x); return slope*1000
def block_ci(times,reps=1000):
    intervals=[(b-a)*1000 for a,b in zip(times,times[1:])]; block=max(1,round(math.sqrt(len(intervals)))); rng=random.Random(20260803); values=[]
    for _ in range(reps):
        sample=[]
        while len(sample)<len(intervals):
            start=rng.randrange(len(intervals)); sample += [intervals[(start+j)%len(intervals)] for j in range(block)]
        values.append(statistics.mean(sample[:len(intervals)]))
    return (pct(values,.975)-pct(values,.025))/2
def interval_metrics(times,expected_interval_ms):
    """Measured interval dispersion; unlike a fitted mean this exposes jitter."""
    if not math.isfinite(expected_interval_ms) or expected_interval_ms<=0: raise ValueError('invalid expected interval')
    intervals=[(b-a)*1000 for a,b in zip(times,times[1:])]
    if not intervals: return {'count':0,'mean_ms':math.inf,'stddev_ms':math.inf,'mad_ms':math.inf,'abs_error_p95_ms':math.inf,'abs_error_max_ms':math.inf}
    median=statistics.median(intervals)
    errors=[abs(x-expected_interval_ms) for x in intervals]
    return {'count':len(intervals),'mean_ms':statistics.mean(intervals),'stddev_ms':statistics.pstdev(intervals),'mad_ms':statistics.median(abs(x-median) for x in intervals),'abs_error_p95_ms':pct(errors,.95),'abs_error_max_ms':max(errors)}
def interval_dispersion_pass(metrics):
    return metrics['abs_error_p95_ms']<=CLICK_INTERVAL_P95_ABS_ERROR_LIMIT_MS and metrics['abs_error_max_ms']<=CLICK_INTERVAL_MAX_ABS_ERROR_LIMIT_MS and metrics['stddev_ms']<=CLICK_INTERVAL_STDDEV_LIMIT_MS and metrics['mad_ms']<=CLICK_INTERVAL_MAD_LIMIT_MS
def pilot_crosstalk_db(path,click_channel,pilot_channel,pilot_times):
    """Compare measured 6 kHz pilot energy in click versus pilot channels."""
    rate,click,_=wav(path,click_channel); pilot_rate,pilot,_=wav(path,pilot_channel)
    if rate!=pilot_rate or not pilot_times: return math.inf
    width=max(16,round(rate*DETECTOR_WINDOW_MS/1000))
    def energy(samples):
        values=[]
        for t in pilot_times:
            start=max(0,round(t*rate)); values.append(goertzel(samples[start:start+width],rate,6000))
        return statistics.median(values) if values else 0.
    return 10*math.log10(max(energy(click),1e-18)/max(energy(pilot),1e-18))
def snr_db(samples,times,rate,window_ms=DETECTOR_WINDOW_MS):
    """RMS SNR over the exact detector windows denoted by `times`."""
    if not times: return -math.inf
    n=max(1,round(window_ms*rate/1000)); sig=[]; used=set()
    for t in times:
        k=round(t*rate); used.update(range(max(0,k),min(len(samples),k+n))); sig+=samples[max(0,k):min(len(samples),k+n)]
    noise=[v for i,v in enumerate(samples) if i not in used]
    rms=lambda z: math.sqrt(sum(v*v for v in z)/max(1,len(z)))
    return 20*math.log10(max(rms(sig),1e-12)/max(rms(noise),1e-12))
def calibration(report):
    d=json.loads(Path(report).read_text()); req=('input','packet_manifest_path','pilot_channel','analysis_start_s','analysis_end_s','expected_interval_ms')
    if d.get('mode')!='calibrate' or any(k not in d for k in req): raise ValueError('invalid calibration report')
    expected=d['expected_interval_ms']
    if type(expected) not in (int,float) or not math.isfinite(float(expected)) or expected<=0: raise ValueError('invalid calibration expected interval')
    m=manifest(d['packet_manifest_path'],d['input']); ts,clip,r=detect(d['input'],d['pilot_channel'],6000)
    ts=[x for x in ts if d['analysis_start_s']<=x<=d['analysis_end_s']]
    if clip or len(ts)<300 or d['analysis_end_s']-d['analysis_start_s']<30 or len(ts)<(d['analysis_end_s']-d['analysis_start_s'])*10-2: raise ValueError('silent/fabricated/underlength calibration')
    observed=fit(ts)
    if abs(observed-float(expected))>CALIBRATION_EXPECTED_TOLERANCE_MS: raise ValueError('calibration expected interval disagrees with observed pilot cadence')
    return m,observed
def analyze(args):
    m=manifest(args.input_packet_manifest,args.input); sch=scheduler(args.scheduler_evidence,m['run_id'])
    cal=[calibration(x) for x in args.calibration_report]
    if len(cal)!=2 or len({x[0]['corrected_wav']['sha256'] for x in cal})!=2 or abs(cal[0][1]-cal[1][1])>.02: raise ValueError('calibration provenance/disagreement')
    clicks,clip,rate=detect(args.input,args.click_channel,1320); clicks=[x for x in clicks if args.analysis_start_s<=x<=args.analysis_end_s]
    pilot,pclip,_=detect(args.input,args.pilot_channel,6000); pilot=[x for x in pilot if args.analysis_start_s<=x<=args.analysis_end_s]
    raw_rate,raw,_=wav(m['raw_pcm_wav']['path'],args.click_channel); raw_clicks,_,_=detect(m['raw_pcm_wav']['path'],args.click_channel,1320)
    residual=[min(abs(x-y) for y in raw_clicks)*1000 for x in clicks] if raw_clicks else [math.inf]
    dup,miss,amb=classify(clicks,.5); fitted=fit(clicks) if len(clicks)>1 else math.inf; ci=block_ci(clicks) if len(clicks)>2 else math.inf
    intervals=interval_metrics(clicks,EXPECTED_CLICK_INTERVAL_MS); crosstalk=pilot_crosstalk_db(args.input,args.click_channel,args.pilot_channel,pilot)
    acoustic=not clip and not pclip and len(clicks)==360 and len(pilot)>= (args.analysis_end_s-args.analysis_start_s)*10-2 and not(dup or miss or amb) and abs(fitted-EXPECTED_CLICK_INTERVAL_MS)<=.5 and interval_dispersion_pass(intervals) and ci<=.1 and crosstalk<=PILOT_CROSSTALK_LIMIT_DB and snr_db(wav(args.input,args.click_channel)[1],clicks,rate)>=20 and pct(residual,.95)<=.25 and max(residual)<=.5
    result={'mode':'analyze','run_id':m['run_id'],'input':str(args.input),'input_sha256':sha(args.input),'packet_manifest_path':str(args.input_packet_manifest),'scheduler_path':str(args.scheduler_evidence),'calibration_reports':[str(x) for x in args.calibration_report],'analysis_start_s':args.analysis_start_s,'analysis_end_s':args.analysis_end_s,'click_channel':args.click_channel,'pilot_channel':args.pilot_channel,'event_timestamp_contract':'analysis_window_start_s','detector_hop_ms':DETECTOR_HOP_MS,'detector_window_ms':DETECTOR_WINDOW_MS,'interval_quantization_ms':DETECTOR_HOP_MS,'click_count':len(clicks),'pilot_count':len(pilot),'expected_click_interval_ms':EXPECTED_CLICK_INTERVAL_MS,'fitted_period_ms':fitted,'fitted_period_ci_half_width_ms':ci,'click_interval_mean_ms':intervals['mean_ms'],'click_interval_stddev_ms':intervals['stddev_ms'],'click_interval_mad_ms':intervals['mad_ms'],'click_interval_abs_error_p95_ms':intervals['abs_error_p95_ms'],'click_interval_abs_error_max_ms':intervals['abs_error_max_ms'],'pilot_crosstalk_db':crosstalk,'snr_db':snr_db(wav(args.input,args.click_channel)[1],clicks,rate),'raw_corrected_residual_p95_ms':pct(residual,.95),'raw_corrected_residual_max_ms':max(residual),'acoustic_pass':acoustic,'scheduler_pass':True,'consumer_qa_only':True,'trace_verification_pending':True,'passed':False}
    return result
def compare(paths):
    if len(paths)!=2 or len({Path(x).resolve() for x in paths})!=2: raise ValueError('compare needs two distinct analysis reports')
    a,b=[json.loads(Path(x).read_text()) for x in paths]
    recomputed=[]
    for x in (a,b):
        if x.get('mode')!='analyze': raise ValueError('invalid analysis report')
        class Args: pass
        z=Args(); z.input=Path(x['input']); z.input_packet_manifest=Path(x['packet_manifest_path']); z.scheduler_evidence=Path(x['scheduler_path']); z.calibration_report=[Path(v) for v in x['calibration_reports']]; z.analysis_start_s=x['analysis_start_s']; z.analysis_end_s=x['analysis_end_s']; z.click_channel=x['click_channel']; z.pilot_channel=x['pilot_channel']; fresh=analyze(z)
        if x.get('run_id')!=fresh['run_id'] or x.get('input_sha256')!=fresh['input_sha256']: raise ValueError('analysis report metadata does not match recomputed artifacts')
        recomputed.append(fresh)
    if recomputed[0]['run_id']==recomputed[1]['run_id'] or recomputed[0]['input_sha256']==recomputed[1]['input_sha256']: raise ValueError('compare requires distinct recomputed run IDs and artifacts')
    return {'mode':'compare','between_run_fitted_period_difference_ms':abs(recomputed[0]['fitted_period_ms']-recomputed[1]['fitted_period_ms']),'consumer_qa_only':True,'trace_verification_pending':True,'passed':False}
def main(argv):
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest='mode',required=True); c=sub.add_parser('calibrate'); a=sub.add_parser('analyze'); q=sub.add_parser('compare')
    for x in(c,a):
        x.add_argument('--input',type=Path,required=True); x.add_argument('--input-packet-manifest',type=Path,required=True); x.add_argument('--analysis-start-s',type=float,required=True); x.add_argument('--analysis-end-s',type=float,required=True); x.add_argument('--output',type=Path)
    c.add_argument('--pilot-channel',type=int,required=True); c.add_argument('--expected-interval-ms',type=float,default=100)
    a.add_argument('--click-channel',type=int,required=True); a.add_argument('--pilot-channel',type=int,required=True); a.add_argument('--scheduler-evidence',type=Path,required=True); a.add_argument('--calibration-report',type=Path,action='append',required=True)
    q.add_argument('--analysis-report',type=Path,action='append',required=True); q.add_argument('--output',type=Path)
    z=p.parse_args(argv)
    if z.mode=='calibrate':
        m=manifest(z.input_packet_manifest,z.input); ts,clip,_=detect(z.input,z.pilot_channel,6000); ts=[x for x in ts if z.analysis_start_s<=x<=z.analysis_end_s]; observed=fit(ts) if len(ts)>1 else math.inf; expected=float(z.expected_interval_ms); expected_matches=math.isfinite(expected) and expected>0 and abs(observed-expected)<=CALIBRATION_EXPECTED_TOLERANCE_MS; out={'mode':'calibrate','input':str(z.input),'packet_manifest_path':str(z.input_packet_manifest),'pilot_channel':z.pilot_channel,'analysis_start_s':z.analysis_start_s,'analysis_end_s':z.analysis_end_s,'event_timestamp_contract':'analysis_window_start_s','detector_hop_ms':DETECTOR_HOP_MS,'detector_window_ms':DETECTOR_WINDOW_MS,'expected_interval_ms':z.expected_interval_ms,'detected_count':len(ts),'fitted_period_ms':observed if math.isfinite(observed) else None,'expected_interval_matches_observed':expected_matches,'acoustic_pass':not clip and len(ts)>=300 and len(ts)>= (z.analysis_end_s-z.analysis_start_s)*10-2 and expected_matches,'passed':False,'trace_verification_pending':True}
    elif z.mode=='analyze': out=analyze(z)
    else: out=compare(z.analysis_report)
    text=json.dumps(out,indent=2,sort_keys=True)+'\n'; z.output.write_text(text) if z.output else sys.stdout.write(text); return 0
if __name__=='__main__':
    try: raise SystemExit(main(sys.argv[1:]))
    except (ValueError,OSError,wave.Error,json.JSONDecodeError) as e: print('ERROR:',e,file=sys.stderr); raise SystemExit(2)
