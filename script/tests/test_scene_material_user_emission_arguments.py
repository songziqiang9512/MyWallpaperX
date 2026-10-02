"""Actual DEBUG CLI parser, including whole-sequence transport rejection."""
import json, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

class SceneMaterialUserEmissionArgumentsTests(unittest.TestCase):
    def test_actual_sequence_parser_and_legacy_single(self):
        with tempfile.TemporaryDirectory(prefix='mwx-property-arguments-') as temporary:
            work=Path(temporary);source=work/'Probe.swift';binary=work/'probe'
            source.write_text('''import Foundation
            enum DebugScenePlaybackRunner {}
            enum SceneUserPropertyTextureLoader { static func supports(url:URL)->Bool { false } }
            @main enum Probe {
                static func main() throws {
                    let value:Any = DebugScenePlaybackRunner.requestedLivePropertySequence.map {
                        $0.map { $0.mapValues { $0.foundationValue } }
                    } as Any? ?? NSNull()
                    print(String(decoding:try JSONSerialization.data(withJSONObject:["value":value]),as:UTF8.self))
                }
            }''')
            sources=[ROOT/'MyWallpaperX/App/DebugScenePlaybackRunner+Arguments.swift',ROOT/'MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift']
            result=subprocess.run(['xcrun','swiftc','-D','DEBUG',*map(str,sources),str(source),'-module-cache-path',str(work/'cache'),'-framework','AppKit','-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            single='--mwx-debug-scene-live-properties-json';sequence='--mwx-debug-scene-live-property-sequence-json'
            cases=[([],[]),([single,'{"a":1}'],[{'a':1}]),([sequence,'[{"a":0},{"a":1},{"a":0}]'],[{'a':0},{'a':1},{'a':0}]),
                ([single,'{"a":1}',sequence,'[]'],[]),([single,'{"a":1}',sequence],None),
                ([single,'{"a":1}',sequence,'bad'],None),([single,'{"a":1}',sequence,'[{"a":0},false]'],None),
                ([sequence,'[{"a":0},{"a":null}]'],None),([sequence,'[{"a":0},{"":1}]'],None),
                ([sequence,json.dumps([dict((str(i),i) for i in range(65))])],None),
                ([sequence,json.dumps([{'a':'x'*65536}])],None),
                ([sequence,'[{"unknown":2},{"a":"bad"}]'],[{'unknown':2},{'a':'bad'}])]
            for args,want in cases:
                result=subprocess.run([str(binary),*args],capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(json.loads(result.stdout)['value'],want,args)
