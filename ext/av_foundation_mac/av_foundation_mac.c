#include <ruby.h>
#include <ruby/thread.h>
#include "AVFoundationMac-Swift.h"

struct capture_options {
    const char *format;
    long width;
    long height;
    double quality;
};

struct call {
    void *(*fn)(void *);
    void *cancel;
    char *result;
};

struct snapshot_args {
    struct call call;
    const char *device_id;
    const char *out_path;
    struct capture_options opts;
};

struct open_session_args {
    struct call call;
    const char *device_id;
    struct capture_options opts;
};

struct capture_frame_args {
    struct call call;
    const char *out_path;
};

static void cancel_call(void *cancel) {
    av_foundation_mac_cancel(cancel);
}

static VALUE call_body(VALUE data) {
    struct call *call = (struct call *)data;
    rb_thread_call_without_gvl(call->fn, call, cancel_call, call->cancel);
    return Qnil;
}

static VALUE call_without_gvl(struct call *call) {
    int state = 0;
    call->cancel = av_foundation_mac_cancel_new();
    rb_protect(call_body, (VALUE)call, &state);
    av_foundation_mac_cancel_free(call->cancel);
    if (state) {
        av_foundation_mac_free(call->result);
        rb_jump_tag(state);
    }
    VALUE str = rb_utf8_str_new_cstr(call->result);
    av_foundation_mac_free(call->result);
    return str;
}

static ID option_keys[4];

static struct capture_options parse_options(VALUE opts) {
    struct capture_options o = { "jpeg", 0, 0, 0.85 };
    if (NIL_P(opts)) return o;

    VALUE values[4];
    rb_get_kwargs(opts, option_keys, 0, 4, values);
    if (!RB_UNDEF_P(values[0])) {
        Check_Type(values[0], T_SYMBOL);
        o.format = rb_id2name(SYM2ID(values[0]));
        if (strcmp(o.format, "jpeg") != 0 && strcmp(o.format, "heic") != 0) {
            rb_raise(rb_eArgError, "unknown format: %"PRIsVALUE" (expected :jpeg or :heic)", rb_inspect(values[0]));
        }
    }
    if (!RB_UNDEF_P(values[1])) o.width = NUM2LONG(values[1]);
    if (!RB_UNDEF_P(values[2])) o.height = NUM2LONG(values[2]);
    if (!RB_UNDEF_P(values[3])) o.quality = NUM2DBL(values[3]);
    return o;
}

static VALUE frozen_string(VALUE str) {
    StringValue(str);
    return rb_str_new_frozen(str);
}

static void *snapshot_no_gvl(void *data) {
    struct snapshot_args *a = data;
    a->call.result = av_foundation_mac_snapshot(a->device_id, a->out_path, a->opts.format,
                                                a->opts.width, a->opts.height, a->opts.quality, a->call.cancel);
    return NULL;
}

static VALUE rb_av_foundation_mac_snapshot(int argc, VALUE *argv, VALUE self) {
    VALUE device_id, out_path, opts;
    rb_scan_args(argc, argv, "2:", &device_id, &out_path, &opts);
    device_id = frozen_string(device_id);
    out_path = frozen_string(out_path);
    struct capture_options o = parse_options(opts);
    struct snapshot_args a = {
        .call = { snapshot_no_gvl },
        .device_id = StringValueCStr(device_id),
        .out_path = StringValueCStr(out_path),
        .opts = o,
    };
    VALUE result = call_without_gvl(&a.call);
    RB_GC_GUARD(device_id);
    RB_GC_GUARD(out_path);
    return result;
}

static void *open_session_no_gvl(void *data) {
    struct open_session_args *a = data;
    a->call.result = av_foundation_mac_open_session(a->device_id, a->opts.format,
                                                    a->opts.width, a->opts.height, a->opts.quality, a->call.cancel);
    return NULL;
}

static VALUE rb_av_foundation_mac_open_session(int argc, VALUE *argv, VALUE self) {
    VALUE device_id, opts;
    rb_scan_args(argc, argv, "1:", &device_id, &opts);
    device_id = frozen_string(device_id);
    struct capture_options o = parse_options(opts);
    struct open_session_args a = {
        .call = { open_session_no_gvl },
        .device_id = StringValueCStr(device_id),
        .opts = o,
    };
    VALUE result = call_without_gvl(&a.call);
    RB_GC_GUARD(device_id);
    return result;
}

static void *capture_frame_no_gvl(void *data) {
    struct capture_frame_args *a = data;
    a->call.result = av_foundation_mac_capture_frame(a->out_path);
    return NULL;
}

static VALUE rb_av_foundation_mac_capture_frame(VALUE self, VALUE out_path) {
    out_path = frozen_string(out_path);
    struct capture_frame_args a = {
        .call = { capture_frame_no_gvl },
        .out_path = StringValueCStr(out_path),
    };
    VALUE result = call_without_gvl(&a.call);
    RB_GC_GUARD(out_path);
    return result;
}

static void *close_session_no_gvl(void *data) {
    av_foundation_mac_close_session();
    return NULL;
}

static VALUE rb_av_foundation_mac_close_session(VALUE self) {
    rb_thread_call_without_gvl(close_session_no_gvl, NULL, NULL, NULL);
    return Qnil;
}

static VALUE rb_av_foundation_mac_devices(VALUE self) {
    char *result = av_foundation_mac_devices();
    VALUE str = rb_utf8_str_new_cstr(result);
    av_foundation_mac_free(result);
    return str;
}

void Init_av_foundation_mac(void) {
    rb_ext_ractor_safe(true);
    option_keys[0] = rb_intern("format");
    option_keys[1] = rb_intern("width");
    option_keys[2] = rb_intern("height");
    option_keys[3] = rb_intern("quality");
    VALUE module = rb_define_module("AVFoundationMac");
    rb_define_singleton_method(module, "devices", rb_av_foundation_mac_devices, 0);
    rb_define_singleton_method(module, "snapshot", rb_av_foundation_mac_snapshot, -1);
    rb_define_singleton_method(module, "open_session", rb_av_foundation_mac_open_session, -1);
    rb_define_singleton_method(module, "capture_frame", rb_av_foundation_mac_capture_frame, 1);
    rb_define_singleton_method(module, "close_session", rb_av_foundation_mac_close_session, 0);
}
