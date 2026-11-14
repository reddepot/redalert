"""Offline Artemis contract probe. No Android device, model or network is used."""
import argparse, asyncio, json, os, socket, subprocess, sys
from pathlib import Path

PIN='351ca8422f7b5b54e80a9c1ce03a222e02415b6b'
parser=argparse.ArgumentParser();parser.add_argument('--checkout',type=Path,required=True);args=parser.parse_args()
checkout=args.checkout.resolve()
head=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
if head!=PIN:raise SystemExit('Artemis version differs from the reviewed pin; inspect before upgrading.')
for name in list(os.environ):
 if any(part in name for part in ['API_KEY','AUTH_TOKEN','REDAPI','OPENROUTER','LANGSMITH','LANGCHAIN']):os.environ.pop(name,None)
root=Path(__file__).resolve().parents[2]
os.environ.update({'ARTEMIS_APP_DIR':str(root/'build/artemis-validation/runtime'),'ARTEMIS_KEEP_DEVICE_AWAKE':'false','DO_NOT_TRACK':'1','ANONYMIZED_TELEMETRY':'false','LANGSMITH_TRACING':'false','LANGCHAIN_TRACING_V2':'false'})
sys.path.insert(0,str(checkout))
def blocked(*args,**kwargs):raise RuntimeError('Network/device I/O forbidden in offline Artemis probe')
socket.socket.connect=blocked
socket.create_connection=blocked
from artemis.mcp.actuators.mock import MockActuator
from artemis.mcp.action_manifest import validate_actuator

async def run():
 actuator=MockActuator(width=1080,height=2400)
 validate_actuator(actuator)
 await actuator.click(500,500)
 assert actuator.action_history, 'No mock click recorded'
 result={'artemis_commit':head,'backend':'MockActuator','contract':'passed','mock_actions':len(actuator.action_history),'device_execution':False,'model_calls':0,'network':'blocked','host_keep_awake':False}
 print(json.dumps(result))
if __name__=='__main__':asyncio.run(run())
