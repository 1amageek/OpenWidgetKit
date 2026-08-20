#ifndef OPEN_WIDGET_WINDOWS_BRIDGE_H
#define OPEN_WIDGET_WINDOWS_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define OWK_CALL __cdecl
#if defined(OPEN_WIDGET_WINDOWS_PROVIDER_EXPORTS)
#define OWK_PROVIDER_API __declspec(dllexport)
#else
#define OWK_PROVIDER_API
#endif
#else
#define OWK_CALL
#define OWK_PROVIDER_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OWKByteSlice {
    /* Borrowed UTF-8 bytes are valid only for the duration of the ABI call. */
    const uint8_t *data;
    size_t count;
} OWKByteSlice;

typedef void (OWK_CALL *OWKReleaseOwnerFunction)(void *owner);

typedef struct OWKOwnedBytes {
    /* The receiver must invoke release_owner(owner) exactly once when nonnull. */
    OWKByteSlice bytes;
    void *owner;
    OWKReleaseOwnerFunction release_owner;
} OWKOwnedBytes;

typedef enum OWKStatusCode {
    OWK_STATUS_OK = 0,
    OWK_STATUS_INVALID_ARGUMENT = 1,
    OWK_STATUS_PLATFORM_UNAVAILABLE = 2,
    OWK_STATUS_LIBRARY_LOAD_FAILED = 3,
    OWK_STATUS_SYMBOL_MISSING = 4,
    OWK_STATUS_COM_FAILURE = 5,
    OWK_STATUS_HOST_REJECTED = 6,
    OWK_STATUS_STALE_GENERATION = 7,
    OWK_STATUS_SHUTTING_DOWN = 8,
    OWK_STATUS_INTERNAL_FAILURE = 9
} OWKStatusCode;

typedef struct OWKResult {
    int32_t code;
    OWKOwnedBytes message;
} OWKResult;

typedef enum OWKWidgetEventKind {
    OWK_EVENT_CREATE = 1,
    OWK_EVENT_DELETE = 2,
    OWK_EVENT_ACTIVATE = 3,
    OWK_EVENT_DEACTIVATE = 4,
    OWK_EVENT_CONTEXT_CHANGED = 5,
    OWK_EVENT_ACTION_INVOKED = 6,
    OWK_EVENT_RECOVER = 7,
    OWK_EVENT_SHUTDOWN_REQUESTED = 8
} OWKWidgetEventKind;

typedef enum OWKWidgetSize {
    OWK_WIDGET_SIZE_SMALL = 1,
    OWK_WIDGET_SIZE_MEDIUM = 2,
    OWK_WIDGET_SIZE_LARGE = 3,
    OWK_WIDGET_SIZE_UNKNOWN = 255
} OWKWidgetSize;

typedef struct OWKWidgetEvent {
    int32_t kind;
    OWKByteSlice widget_id;
    OWKByteSlice definition_id;
    OWKByteSlice custom_state;
    OWKByteSlice action_verb;
    OWKByteSlice action_data;
    int32_t widget_size;
    int32_t is_active;
    /* All slices above borrow this owner and must not escape the callback. */
    void *owner;
    OWKReleaseOwnerFunction release_owner;
} OWKWidgetEvent;

typedef void (OWK_CALL *OWKEventCallback)(
    void *context,
    const OWKWidgetEvent *event
);

typedef void (OWK_CALL *OWKDiagnosticCallback)(
    void *context,
    int32_t code,
    OWKOwnedBytes message
);

typedef struct OWKCallbacks {
    void *context;
    OWKEventCallback on_event;
    OWKDiagnosticCallback on_diagnostic;
} OWKCallbacks;

typedef struct OWKProviderConfiguration {
    OWKByteSlice class_id;
    OWKCallbacks callbacks;
} OWKProviderConfiguration;

typedef struct OWKProviderHandle OWKProviderHandle;
typedef struct OWKBridgeHandle OWKBridgeHandle;

OWKResult OWK_CALL owk_bridge_open(
    OWKByteSlice library_path,
    const OWKProviderConfiguration *configuration,
    OWKBridgeHandle **handle
);
OWKResult OWK_CALL owk_bridge_run(OWKBridgeHandle *handle);
OWKResult OWK_CALL owk_bridge_request_shutdown(OWKBridgeHandle *handle);
OWKResult OWK_CALL owk_bridge_complete_shutdown(OWKBridgeHandle *handle);
OWKResult OWK_CALL owk_bridge_invalidate(
    OWKBridgeHandle *handle,
    OWKByteSlice widget_id,
    uint64_t generation
);
OWKResult OWK_CALL owk_bridge_update(
    OWKBridgeHandle *handle,
    OWKByteSlice widget_id,
    uint64_t generation,
    /* An empty template slice preserves the template already stored by the host. */
    OWKByteSlice template_json,
    OWKByteSlice data_json,
    OWKByteSlice custom_state
);
OWKResult OWK_CALL owk_bridge_remove(
    OWKBridgeHandle *handle,
    OWKByteSlice widget_id,
    uint64_t generation
);
void OWK_CALL owk_bridge_close(OWKBridgeHandle *handle);

OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_create(
    const OWKProviderConfiguration *configuration,
    OWKProviderHandle **handle
);
OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_run(OWKProviderHandle *handle);
OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_request_shutdown(
    OWKProviderHandle *handle
);
OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_complete_shutdown(
    OWKProviderHandle *handle
);
OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_invalidate(
    OWKProviderHandle *handle,
    OWKByteSlice widget_id,
    uint64_t generation
);
OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_update(
    OWKProviderHandle *handle,
    OWKByteSlice widget_id,
    uint64_t generation,
    /* An empty template slice preserves the template already stored by the host. */
    OWKByteSlice template_json,
    OWKByteSlice data_json,
    OWKByteSlice custom_state
);
OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_remove(
    OWKProviderHandle *handle,
    OWKByteSlice widget_id,
    uint64_t generation
);
OWK_PROVIDER_API void OWK_CALL owk_provider_destroy(OWKProviderHandle *handle);

#ifdef __cplusplus
}
#endif

#endif
