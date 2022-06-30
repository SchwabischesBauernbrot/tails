#include "Python.h"
#include "pygobject.h"
#include "zbargtk.h"

static ZBarGtk *pyobject_to_zbar(PyObject *object)
{
    GObject *gobj = NULL;
    ZBarGtk *zbar = NULL;
    if (
            !pygobject_check(object, &PyGObject_Type) ||
            !(gobj = pygobject_get(object)) ||
            !ZBAR_IS_GTK(gobj) ||
            !(zbar = ZBAR_GTK(gobj))) {
        PyErr_SetString(PyExc_TypeError, "Not a ZBarGtk object");
    }
    return zbar;
}

static PyObject *create_widget(PyObject *self, PyObject *args)
{
    GtkWidget *widget = zbar_gtk_new();
    if (!widget) {
        return PyErr_NoMemory();
    }
    return pygobject_new(G_OBJECT(widget));
}

static PyObject *request_video_size(PyObject *self, PyObject *args)
{
    PyObject *object;
    ZBarGtk *zbar;
    int width, height;
    if (!PyArg_ParseTuple(args, "Oii", &object, &width, &height) ||
            !(zbar = pyobject_to_zbar(object))) {
        return NULL;
    }
    zbar_gtk_request_video_size(zbar, width, height);
    Py_RETURN_NONE;
}

static PyMethodDef ZbargtkMethods[] = {
    { "create_widget", create_widget, METH_NOARGS, "Create a new barcode reader widget instance without any associated video device or image." },
    { "request_video_size", request_video_size, METH_VARARGS, "Set video camera resolution. This call must be made before video is initialized." },
    { NULL, NULL, 0, NULL }
};

static struct PyModuleDef zbargtkmozule = {
    PyModuleDef_HEAD_INIT, "zbargtk", "", -1, ZbargtkMethods
};

PyMODINIT_FUNC PyInit_zbargtk(void)
{
    PyObject *module = PyModule_Create(&zbargtkmozule);
    if (!module)
        return NULL;
    pygobject_init(-1, -1, -1);
    return module;
}
