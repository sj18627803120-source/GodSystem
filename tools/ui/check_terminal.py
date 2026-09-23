"""Run focused terminal behavior checks with the same fixture as its preview."""
from preview_terminal import create_vm, ROOT
vm=create_vm()
vm.globals().readFixture=lambda name: ''  # create_vm already installed the shared fixture.
vm.execute((ROOT/'tools/tests/terminal_spec.lua').read_text(encoding='utf-8'))
