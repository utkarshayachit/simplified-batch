import paraview.web.venv  # Available in PV 5.10

from trame.app import get_server
from trame.widgets import vuetify, paraview
from trame.ui.vuetify import SinglePageLayout, VAppLayout

from paraview import simple as pvs

server = get_server()
state, ctrl = server.state, server.controller

view = pvs.CreateRenderView()
def setup_pipeline(filename, view):
    reader = pvs.OpenDataFile(filename)
    display = pvs.Show(reader, view)
    view.StillRender()
    view.ResetCamera()
    view.CenterOfRotation = view.CameraFocalPoint

# -----------------------------------------------------------------------------
# trame setup
# -----------------------------------------------------------------------------

with VAppLayout(server) as layout:
    with layout.root:
        with vuetify.VContainer(fluid=True,
            classes='fill-height pa-0'):
            htmlView = paraview.VtkRemoteView(view,
                interactive_ratio=0.5)
            ctrl.reset_camera = htmlView.reset_camera

def touch(filename):
    def create(*args, **kwargs):
        with open(filename, 'w') as f:
            f.write('server ready')
    return create

if __name__ == '__main__':
    server.cli.add_argument('--dataset', help='dataset to load')
    server.cli.add_argument('--create-on-server-ready',
        help='file to create when server is ready')

    args = server.cli.parse_known_args()[0]
    if args.dataset is not None:
        setup_pipeline(args.dataset, view)
    else:
        s = pvs.Sphere()
        pvs.Show(s, view)

    if args.create_on_server_ready is not None:
        ctrl.on_server_ready.add(touch(args.create_on_server_ready))
    server.start()
