#include "OpenWidgetWindowsBridge.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>

typedef OWKResult (OWK_CALL *CreateFunction)(
    const OWKProviderConfiguration *,
    OWKProviderHandle **
);
typedef OWKResult (OWK_CALL *UnaryFunction)(OWKProviderHandle *);
typedef OWKResult (OWK_CALL *GenerationFunction)(
    OWKProviderHandle *,
    OWKByteSlice,
    uint64_t
);
typedef OWKResult (OWK_CALL *UpdateFunction)(
    OWKProviderHandle *,
    OWKByteSlice,
    uint64_t,
    OWKByteSlice,
    OWKByteSlice,
    OWKByteSlice
);
typedef void (OWK_CALL *DestroyFunction)(OWKProviderHandle *);

struct OWKBridgeHandle {
    HMODULE module;
    OWKProviderHandle *provider;
    UnaryFunction run;
    UnaryFunction request_shutdown;
    UnaryFunction complete_shutdown;
    GenerationFunction invalidate;
    UpdateFunction update;
    GenerationFunction remove;
    DestroyFunction destroy;
};

static OWKOwnedBytes static_message(const char *message) {
    OWKOwnedBytes value = {
        {(const uint8_t *)message, message == NULL ? 0 : strlen(message)},
        NULL,
        NULL
    };
    return value;
}

static OWKResult failure(int32_t code, const char *message) {
    OWKResult result = {code, static_message(message)};
    return result;
}

static void OWK_CALL release_loader_message(void *owner) {
    free(owner);
}

static OWKResult copy_provider_failure(OWKResult provider_result) {
    const size_t count = provider_result.message.bytes.count;
    uint8_t *copy = NULL;
    if (count > 0) {
        if (provider_result.message.bytes.data == NULL) {
            if (provider_result.message.release_owner != NULL) {
                provider_result.message.release_owner(provider_result.message.owner);
            }
            return failure(OWK_STATUS_INTERNAL_FAILURE, "The provider returned an invalid error buffer.");
        }
        copy = (uint8_t *)malloc(count);
        if (copy == NULL) {
            if (provider_result.message.release_owner != NULL) {
                provider_result.message.release_owner(provider_result.message.owner);
            }
            return failure(OWK_STATUS_INTERNAL_FAILURE, "Unable to retain the provider error before unloading its library.");
        }
        memcpy(copy, provider_result.message.bytes.data, count);
    }
    if (provider_result.message.release_owner != NULL) {
        provider_result.message.release_owner(provider_result.message.owner);
    }
    OWKResult copied = {
        provider_result.code,
        {{copy, count}, copy, copy == NULL ? NULL : release_loader_message}
    };
    return copied;
}

static FARPROC required_symbol(HMODULE module, const char *name) {
    return GetProcAddress(module, name);
}

OWKResult OWK_CALL owk_bridge_open(
    OWKByteSlice library_path,
    const OWKProviderConfiguration *configuration,
    OWKBridgeHandle **handle
) {
    if (configuration == NULL || handle == NULL
        || configuration->callbacks.on_event == NULL
        || library_path.data == NULL
        || library_path.count > INT_MAX) {
        return failure(OWK_STATUS_INVALID_ARGUMENT, "Invalid bridge configuration.");
    }
    *handle = NULL;
    int wide_count = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        (const char *)library_path.data,
        (int)library_path.count,
        NULL,
        0
    );
    if (wide_count <= 0) {
        return failure(OWK_STATUS_INVALID_ARGUMENT, "The bridge path is not valid UTF-8.");
    }
    wchar_t *wide_path = (wchar_t *)calloc((size_t)wide_count + 1, sizeof(wchar_t));
    if (wide_path == NULL) {
        return failure(OWK_STATUS_INTERNAL_FAILURE, "Unable to allocate the bridge path.");
    }
    const int converted_count = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        (const char *)library_path.data,
        (int)library_path.count,
        wide_path,
        wide_count
    );
    if (converted_count != wide_count) {
        free(wide_path);
        return failure(OWK_STATUS_INVALID_ARGUMENT, "The bridge path could not be converted to UTF-16.");
    }
    HMODULE module = LoadLibraryW(wide_path);
    free(wide_path);
    if (module == NULL) {
        return failure(OWK_STATUS_LIBRARY_LOAD_FAILED, "OpenWidgetWindowsBridge.dll could not be loaded.");
    }

    CreateFunction create = (CreateFunction)required_symbol(module, "owk_provider_create");
    OWKBridgeHandle *value = (OWKBridgeHandle *)calloc(1, sizeof(OWKBridgeHandle));
    if (value == NULL) {
        FreeLibrary(module);
        return failure(OWK_STATUS_INTERNAL_FAILURE, "Unable to allocate the bridge handle.");
    }
    value->module = module;
    value->run = (UnaryFunction)required_symbol(module, "owk_provider_run");
    value->request_shutdown = (UnaryFunction)required_symbol(module, "owk_provider_request_shutdown");
    value->complete_shutdown = (UnaryFunction)required_symbol(module, "owk_provider_complete_shutdown");
    value->invalidate = (GenerationFunction)required_symbol(module, "owk_provider_invalidate");
    value->update = (UpdateFunction)required_symbol(module, "owk_provider_update");
    value->remove = (GenerationFunction)required_symbol(module, "owk_provider_remove");
    value->destroy = (DestroyFunction)required_symbol(module, "owk_provider_destroy");
    if (create == NULL || value->run == NULL || value->request_shutdown == NULL
        || value->complete_shutdown == NULL || value->invalidate == NULL
        || value->update == NULL || value->remove == NULL || value->destroy == NULL) {
        free(value);
        FreeLibrary(module);
        return failure(OWK_STATUS_SYMBOL_MISSING, "The provider bridge ABI is incomplete.");
    }
    OWKResult result = create(configuration, &value->provider);
    if (result.code != OWK_STATUS_OK) {
        OWKResult copied_result = copy_provider_failure(result);
        free(value);
        FreeLibrary(module);
        return copied_result;
    }
    if (value->provider == NULL) {
        if (result.message.release_owner != NULL) {
            result.message.release_owner(result.message.owner);
        }
        free(value);
        FreeLibrary(module);
        return failure(
            OWK_STATUS_INTERNAL_FAILURE,
            "The provider returned success without a provider handle."
        );
    }
    *handle = value;
    return result;
}

OWKResult OWK_CALL owk_bridge_run(OWKBridgeHandle *handle) {
    if (handle == NULL) return failure(OWK_STATUS_INVALID_ARGUMENT, "Bridge handle is null.");
    return handle->run(handle->provider);
}

OWKResult OWK_CALL owk_bridge_request_shutdown(OWKBridgeHandle *handle) {
    if (handle == NULL) return failure(OWK_STATUS_INVALID_ARGUMENT, "Bridge handle is null.");
    return handle->request_shutdown(handle->provider);
}

OWKResult OWK_CALL owk_bridge_complete_shutdown(OWKBridgeHandle *handle) {
    if (handle == NULL) return failure(OWK_STATUS_INVALID_ARGUMENT, "Bridge handle is null.");
    return handle->complete_shutdown(handle->provider);
}

OWKResult OWK_CALL owk_bridge_invalidate(
    OWKBridgeHandle *handle,
    OWKByteSlice widget_id,
    uint64_t generation
) {
    if (handle == NULL) return failure(OWK_STATUS_INVALID_ARGUMENT, "Bridge handle is null.");
    return handle->invalidate(handle->provider, widget_id, generation);
}

OWKResult OWK_CALL owk_bridge_update(
    OWKBridgeHandle *handle,
    OWKByteSlice widget_id,
    uint64_t generation,
    OWKByteSlice template_json,
    OWKByteSlice data_json,
    OWKByteSlice custom_state
) {
    if (handle == NULL) return failure(OWK_STATUS_INVALID_ARGUMENT, "Bridge handle is null.");
    return handle->update(
        handle->provider,
        widget_id,
        generation,
        template_json,
        data_json,
        custom_state
    );
}

OWKResult OWK_CALL owk_bridge_remove(
    OWKBridgeHandle *handle,
    OWKByteSlice widget_id,
    uint64_t generation
) {
    if (handle == NULL) return failure(OWK_STATUS_INVALID_ARGUMENT, "Bridge handle is null.");
    return handle->remove(handle->provider, widget_id, generation);
}

void OWK_CALL owk_bridge_close(OWKBridgeHandle *handle) {
    if (handle == NULL) return;
    handle->destroy(handle->provider);
    FreeLibrary(handle->module);
    free(handle);
}

#else

struct OWKBridgeHandle { uint8_t unused; };

static OWKResult platform_unavailable(void) {
    static const char message[] = "The Windows widget provider bridge is available only on Windows.";
    OWKResult result = {
        OWK_STATUS_PLATFORM_UNAVAILABLE,
        {{(const uint8_t *)message, sizeof(message) - 1}, NULL, NULL}
    };
    return result;
}

OWKResult OWK_CALL owk_bridge_open(
    OWKByteSlice library_path,
    const OWKProviderConfiguration *configuration,
    OWKBridgeHandle **handle
) {
    (void)library_path;
    (void)configuration;
    if (handle != NULL) *handle = NULL;
    return platform_unavailable();
}
OWKResult OWK_CALL owk_bridge_run(OWKBridgeHandle *handle) { (void)handle; return platform_unavailable(); }
OWKResult OWK_CALL owk_bridge_request_shutdown(OWKBridgeHandle *handle) { (void)handle; return platform_unavailable(); }
OWKResult OWK_CALL owk_bridge_complete_shutdown(OWKBridgeHandle *handle) { (void)handle; return platform_unavailable(); }
OWKResult OWK_CALL owk_bridge_invalidate(OWKBridgeHandle *handle, OWKByteSlice widget_id, uint64_t generation) { (void)handle; (void)widget_id; (void)generation; return platform_unavailable(); }
OWKResult OWK_CALL owk_bridge_update(OWKBridgeHandle *handle, OWKByteSlice widget_id, uint64_t generation, OWKByteSlice template_json, OWKByteSlice data_json, OWKByteSlice custom_state) { (void)handle; (void)widget_id; (void)generation; (void)template_json; (void)data_json; (void)custom_state; return platform_unavailable(); }
OWKResult OWK_CALL owk_bridge_remove(OWKBridgeHandle *handle, OWKByteSlice widget_id, uint64_t generation) { (void)handle; (void)widget_id; (void)generation; return platform_unavailable(); }
void OWK_CALL owk_bridge_close(OWKBridgeHandle *handle) { (void)handle; }

#endif
