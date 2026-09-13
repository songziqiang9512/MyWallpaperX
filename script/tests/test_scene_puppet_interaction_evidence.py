import unittest
from script.scene_puppet_interaction_evidence import collect_puppet_interaction_evidence


def fixture(*, changed=True, returned=True, terminal=True):
    lines = []
    def line(time, body):
        lines.append(f'2026-09-10 12:00:{time} App[1] {body}')
    line('01.000', 'phase=pointer-state state=press')
    line('02.000', 'phase=pointer-state state=drag')
    line('03.000', 'phase=pointer-state state=release')
    for time, frame, digest, displacement in [
        ('00.100',1,'baseline',0),('00.200',2,'baseline',0),
        ('02.300',22,'drag' if changed else 'baseline',60 if changed else 0),
        ('08.000',80,'baseline' if returned else 'drag',0),
        ('08.100',81,'baseline' if returned else 'drag',0),
        ('08.200',82,'baseline' if returned else 'drag',0)]:
        line(time, f'phase=puppet-bone-output layer=42 frame={frame} revision=1 '
             f'geometrySHA256={digest} maxBindDisplacement={displacement} scriptWritten={"true" if frame == 22 and changed else "false"} gpu=completed')
        if terminal:
            line(time, f'axis=graph-execution layer=42 frame={frame} gpuCompletion=completed '
                 'compositorConsumed=true outcome=succeeded')
    return '\n'.join(lines)


class PuppetInteractionEvidenceTests(unittest.TestCase):
    def test_requires_changed_geometry_then_exact_return_on_later_terminal_frames(self):
        self.assertTrue(collect_puppet_interaction_evidence(fixture(), [42], response='spring-return')['passed'])

    def test_cpu_change_or_unconsumed_gpu_output_is_not_visible_evidence(self):
        for options in [{'terminal':False},{'changed':False},{'returned':False}]:
            self.assertFalse(collect_puppet_interaction_evidence(fixture(**options), [42], response='spring-return')['passed'])

    def test_unknown_layer_missing_edges_and_wrong_response_cannot_pass(self):
        for log, layers, response in [(fixture(),[43],'spring-return'),('',[42],'spring-return'),(fixture(),[42],'unknown')]:
            self.assertFalse(collect_puppet_interaction_evidence(log,layers,response=response)['passed'])

    def test_outside_capture_requires_unchanged_geometry(self):
        self.assertTrue(collect_puppet_interaction_evidence(fixture(changed=False), [42],response='no-capture')['passed'])
        self.assertFalse(collect_puppet_interaction_evidence(fixture(),[42],response='no-capture')['passed'])

    def test_no_capture_requires_terminal_and_no_hidden_pose_writes(self):
        log = fixture(changed=False)
        self.assertFalse(collect_puppet_interaction_evidence(fixture(changed=False, terminal=False), [42], response='no-capture')['passed'])
        self.assertFalse(collect_puppet_interaction_evidence(log.replace('scriptWritten=false', 'scriptWritten=true'), [42], response='no-capture')['passed'])
