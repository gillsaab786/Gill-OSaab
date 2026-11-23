project('gosaab-wm', 'c',
  version: '0.4.0',
  license: 'MIT',
  default_options: ['c_std=c11', 'warning_level=2', 'werror=false', 'buildtype=release'])

add_project_arguments(
  '-DWLR_USE_UNSTABLE',
  '-DGOSAAB_WM_VERSION="@0@"'.format(meson.project_version()),
  '-Wno-unused-parameter',
  language: 'c')

cc = meson.get_compiler('c')
wayland_server = dependency('wayland-server')
wayland_protos = dependency('wayland-protocols')
wlroots = dependency('wlroots-0.20')
scenefx = dependency('scenefx-0.5')
xkbcommon = dependency('xkbcommon')
math = cc.find_library('m')
pangocairo = dependency('pangocairo')
cairo = dependency('cairo')
libdrm = dependency('libdrm')
libinput = dependency('libinput')

# Protocol headers that wlroots' public headers include
wayland_scanner = find_program('wayland-scanner')
wl_protocol_dir = wayland_protos.get_variable('pkgdatadir')
protocols = [
  wl_protocol_dir / 'stable/tablet/tablet-v2.xml',
  wl_protocol_dir / 'stable/xdg-shell/xdg-shell.xml',
  wl_protocol_dir / 'staging/cursor-shape/cursor-shape-v1.xml',
  wl_protocol_dir / 'unstable/xdg-output/xdg-output-unstable-v1.xml',
  wl_protocol_dir / 'unstable/xdg-decoration/xdg-decoration-unstable-v1.xml',
  wl_protocol_dir / 'unstable/pointer-constraints/pointer-constraints-unstable-v1.xml',
  wl_protocol_dir / 'unstable/relative-pointer/relative-pointer-unstable-v1.xml',
  wl_protocol_dir / 'unstable/pointer-gestures/pointer-gestures-unstable-v1.xml',
  wl_protocol_dir / 'staging/ext-session-lock/ext-session-lock-v1.xml',
  wl_protocol_dir / 'staging/xdg-activation/xdg-activation-v1.xml',
  'protocols/wlr-layer-shell-unstable-v1.xml',
]
protocol_headers = []
foreach xml : protocols
  protocol_headers += custom_target(
    xml.underscorify() + '_server_h',
    input: xml,
    output: '@BASENAME@-protocol.h',
    command: [wayland_scanner, 'server-header', '@INPUT@', '@OUTPUT@'])
endforeach

executable('gosaab-wm',
  ['gosaab-wm.c', 'text.c'] + protocol_headers,
  # scenefx must come before wlroots: both export wlr_scene_*, and scenefx's must win
  dependencies: [scenefx, wayland_server, wlroots, xkbcommon, pangocairo, cairo, libdrm, libinput, math],
  install: true)

test_anim = executable('test-anim', 'tests/test_anim.c', dependencies: [math])
test('animation curves', test_anim)

test_frame = executable('test-frame', 'tests/test_frame.c')
test('window frame hit-testing', test_frame)
test_overview = executable('test-overview', 'tests/test_overview.c', dependencies: [math])
test('mission control layout', test_overview)
