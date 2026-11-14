"""Build complete French phrases locally with sherpa-onnx 1.12.32 + Piper SIWIS.
Usage: python build_pack.py /path/to/vits-piper-fr_FR-siwis-medium
Use --reuse only to reuse matching previously generated utterances.
Only the encoded utterances, manifest and script ship; no inference on Android.
"""
import hashlib,json,subprocess,sys,tempfile
from pathlib import Path
import sherpa_onnx,soundfile
root=Path(__file__).resolve().parents[2];model=Path(sys.argv[1]);out=root/'assets/voice/fr';out.mkdir(parents=True,exist_ok=True)
tts=sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=str(model/'fr_FR-siwis-medium.onnx'),tokens=str(model/'tokens.txt'),data_dir=str(model/'espeak-ng-data')),num_threads=2,debug=False)))
words={30:'trente mètres',50:'cinquante mètres',75:'soixante-quinze mètres',100:'cent mètres',150:'cent cinquante mètres',200:'deux cents mètres',250:'deux cent cinquante mètres',300:'trois cents mètres',400:'quatre cents mètres',500:'cinq cents mètres',600:'six cents mètres',750:'sept cent cinquante mètres',1000:'un kilomètre',1250:'un kilomètre deux cent cinquante mètres',1500:'un kilomètre cinq cents mètres',2000:'deux kilomètres',2500:'deux kilomètres cinq cents mètres',3000:'trois kilomètres'}
types={'fixedCamera':'Radar fixe','redLightCamera':'Radar de feu rouge','averageSpeedCamera':'Radar de tronçon','levelCrossing':'Passage à niveau','levelCrossingLowClearance':'Passage à niveau difficile','highSpeedBump':'Ralentisseur','dangerZone':'Zone de vigilance','sharpTurn':'Virage serré','rumbleStrip':'Bandes rugueuses','roadDip':'Creux de chaussée','roadNarrowing':'Chaussée rétrécie','steepDescent':'Forte descente','roadWorks':'Travaux','trafficJam':'Ralentissement','other':'Lieu enregistré'}
phrases={f'{t}_{d}':f'{name}, à environ {w}.' for t,name in types.items() for d,w in words.items()}
phrases.update({f'{t}_near':f'{name} à proximité.' for t,name in types.items()})
phrases['speed_warning']='Vérifiez votre vitesse.'
phrases['position_lost']='Position indisponible. Alertes suspendues.'
manifest={'voice':'Piper fr_FR-siwis-medium','runtime':f'sherpa-onnx {sherpa_onnx.__version__}','model_url':'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-siwis-medium.tar.bz2','model_sha256':hashlib.sha256((model/'fr_FR-siwis-medium.onnx').read_bytes()).hexdigest(),'speed':1.08,'utterances':{}}
previous=json.loads((out/'manifest.json').read_text()) if (out/'manifest.json').exists() else {}
reuse='--reuse' in sys.argv and all(previous.get(k)==manifest.get(k) for k in ['voice','runtime','model_sha256','speed'])
with tempfile.TemporaryDirectory() as tmp:
 for key,text in phrases.items():
  path=out/f'{key}.ogg'
  if not (reuse and path.exists() and previous.get('utterances',{}).get(key,{}).get('text')==text):
   audio=tts.generate(text,sid=0,speed=1.08)
   wav=Path(tmp)/'phrase.wav';soundfile.write(str(wav),audio.samples,audio.sample_rate)
   subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-af','loudnorm=I=-18:TP=-2:LRA=7','-c:a','libopus','-b:a','32k',str(path)],check=True)
  duration=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',str(path)]))
  manifest['utterances'][key]={'text':text,'seconds':duration,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
  print(key,round(duration,2),flush=True)
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
