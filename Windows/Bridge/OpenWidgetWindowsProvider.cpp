#define OPEN_WIDGET_WINDOWS_PROVIDER_EXPORTS

#include <windows.h>
#include <objbase.h>
#include <roapi.h>

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <new>
#include <optional>
#include <string>
#include <stdexcept>
#include <thread>
#include <unordered_map>
#include <utility>

void open_widget_module_released() noexcept;

namespace winrt {
inline auto get_module_lock() noexcept {
    struct service_lock {
        uint32_t operator++() noexcept {
            return ::CoAddRefServerProcess();
        }

        uint32_t operator--() noexcept {
            const auto count = ::CoReleaseServerProcess();
            if (count == 0) {
                open_widget_module_released();
            }
            return count;
        }
    };
    return service_lock{};
}
}

#define WINRT_CUSTOM_MODULE_LOCK
#include <winrt/base.h>
#include <winrt/Microsoft.Windows.Widgets.h>
#include <winrt/Microsoft.Windows.Widgets.Providers.h>

#include "OpenWidgetWindowsBridge.h"

namespace widgets = winrt::Microsoft::Windows::Widgets;
namespace providers = winrt::Microsoft::Windows::Widgets::Providers;

namespace {

struct ResultOwner {
    std::string value;
};

void OWK_CALL release_result_owner(void* owner) {
    delete static_cast<ResultOwner*>(owner);
}

OWKResult success() noexcept {
    return {OWK_STATUS_OK, {{nullptr, 0}, nullptr, nullptr}};
}

OWKResult failure(int32_t code, std::string message) noexcept {
    auto owner = new (std::nothrow) ResultOwner{std::move(message)};
    if (owner == nullptr) {
        return {OWK_STATUS_INTERNAL_FAILURE, {{nullptr, 0}, nullptr, nullptr}};
    }
    return {
        code,
        {
            {
                reinterpret_cast<const uint8_t*>(owner->value.data()),
                owner->value.size()
            },
            owner,
            release_result_owner
        }
    };
}

OWKResult current_exception() noexcept {
    try {
        throw;
    } catch (winrt::hresult_error const& error) {
        return failure(
            OWK_STATUS_COM_FAILURE,
            winrt::to_string(error.message())
        );
    } catch (std::exception const& error) {
        return failure(OWK_STATUS_INTERNAL_FAILURE, error.what());
    } catch (...) {
        return failure(OWK_STATUS_INTERNAL_FAILURE, "Unknown C++ provider failure.");
    }
}

std::string copy_slice(OWKByteSlice value) {
    if (value.count == 0) {
        return {};
    }
    if (value.data == nullptr) {
        throw std::invalid_argument("A nonempty byte slice has a null pointer.");
    }
    return {
        reinterpret_cast<const char*>(value.data),
        value.count
    };
}

struct EventOwner {
    std::string widget_id;
    std::string definition_id;
    std::string custom_state;
    std::string action_verb;
    std::string action_data;
};

void OWK_CALL release_event_owner(void* owner) {
    delete static_cast<EventOwner*>(owner);
}

OWKByteSlice slice(std::string const& value) noexcept {
    return {
        reinterpret_cast<const uint8_t*>(value.data()),
        value.size()
    };
}

int32_t widget_size(providers::WidgetContext const& context) {
    switch (context.Size()) {
    case widgets::WidgetSize::Small:
        return OWK_WIDGET_SIZE_SMALL;
    case widgets::WidgetSize::Medium:
        return OWK_WIDGET_SIZE_MEDIUM;
    case widgets::WidgetSize::Large:
        return OWK_WIDGET_SIZE_LARGE;
    default:
        return OWK_WIDGET_SIZE_UNKNOWN;
    }
}

class BridgeState : public std::enable_shared_from_this<BridgeState> {
public:
    explicit BridgeState(OWKProviderConfiguration const& configuration)
        : callbacks_(configuration.callbacks),
          class_id_(parse_class_id(copy_slice(configuration.class_id))),
          shutdown_completed_(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {
        if (!shutdown_completed_) {
            throw winrt::hresult_error(HRESULT_FROM_WIN32(GetLastError()));
        }
        operation_thread_ = std::thread([this] { process_operations(); });
    }

    ~BridgeState() {
        {
            std::lock_guard lock(operation_mutex_);
            stop_operations_ = true;
        }
        operation_condition_.notify_one();
        if (operation_thread_.joinable()) {
            operation_thread_.join();
        }
    }

    GUID const& class_id() const noexcept {
        return class_id_;
    }

    OWKResult run();

    OWKResult invalidate(std::string widget_id, uint64_t generation) noexcept {
        try {
            std::lock_guard lock(instance_mutex_);
            auto& instance = instances_[std::move(widget_id)];
            if (generation < instance.generation
                || (instance.deleted && generation <= instance.generation)) {
                return failure(OWK_STATUS_STALE_GENERATION, "Stale widget generation.");
            }
            instance.generation = generation;
            instance.deleted = false;
            return success();
        } catch (...) {
            return current_exception();
        }
    }

    OWKResult update(
        std::string widget_id,
        uint64_t generation,
        std::optional<std::string> template_json,
        std::string data_json,
        std::string custom_state
    ) noexcept {
        try {
            {
                std::lock_guard lock(instance_mutex_);
                auto iterator = instances_.find(widget_id);
                if (iterator == instances_.end()
                    || iterator->second.deleted
                    || iterator->second.generation != generation) {
                    return failure(OWK_STATUS_STALE_GENERATION, "Stale widget generation.");
                }
            }
            return enqueue_and_wait(
                [this,
                 widget_id = std::move(widget_id),
                 generation,
                 template_json = std::move(template_json),
                 data_json = std::move(data_json),
                 custom_state = std::move(custom_state)]() noexcept -> OWKResult {
                    try {
                        {
                            std::lock_guard lock(instance_mutex_);
                            auto iterator = instances_.find(widget_id);
                            if (iterator == instances_.end()
                                || iterator->second.deleted
                                || iterator->second.generation != generation) {
                                return failure(
                                    OWK_STATUS_STALE_GENERATION,
                                    "Stale widget generation."
                                );
                            }
                        }
                        auto options = providers::WidgetUpdateRequestOptions(
                            winrt::to_hstring(widget_id)
                        );
                        if (template_json.has_value()) {
                            options.Template(winrt::to_hstring(*template_json));
                        }
                        options.Data(winrt::to_hstring(data_json));
                        options.CustomState(winrt::to_hstring(custom_state));
                        providers::WidgetManager::GetDefault().UpdateWidget(options);
                        {
                            std::lock_guard lock(instance_mutex_);
                            auto iterator = instances_.find(widget_id);
                            if (iterator == instances_.end()
                                || iterator->second.deleted
                                || iterator->second.generation != generation) {
                                return failure(
                                    OWK_STATUS_STALE_GENERATION,
                                    "The widget lifetime changed while the host update was in flight."
                                );
                            }
                        }
                        return success();
                    } catch (...) {
                        return current_exception();
                    }
                }
            );
        } catch (...) {
            return current_exception();
        }
    }

    OWKResult remove(std::string widget_id, uint64_t generation) noexcept {
        try {
            {
                std::lock_guard lock(instance_mutex_);
                auto& instance = instances_[widget_id];
                if (generation < instance.generation) {
                    return failure(OWK_STATUS_STALE_GENERATION, "Stale widget generation.");
                }
                instance.generation = generation;
                instance.deleted = true;
            }
            return enqueue_and_wait([]() noexcept { return success(); });
        } catch (...) {
            return current_exception();
        }
    }

    void host_created(std::string const& widget_id) {
        std::lock_guard lock(instance_mutex_);
        instances_.try_emplace(widget_id);
    }

    void host_deleted(std::string const& widget_id) {
        std::lock_guard lock(instance_mutex_);
        auto& instance = instances_[widget_id];
        instance.deleted = true;
    }

    void emit(
        int32_t kind,
        std::string widget_id = {},
        std::string definition_id = {},
        std::string custom_state = {},
        std::string action_verb = {},
        std::string action_data = {},
        int32_t size = OWK_WIDGET_SIZE_UNKNOWN,
        bool is_active = false
    ) noexcept {
        if (kind != OWK_EVENT_SHUTDOWN_REQUESTED) {
            std::lock_guard lock(shutdown_mutex_);
            if (shutdown_requested_) {
                return;
            }
        }
        if (callbacks_.on_event == nullptr) {
            return;
        }
        if (kind == OWK_EVENT_SHUTDOWN_REQUESTED) {
            // Shutdown has no payload and must not depend on heap allocation;
            // otherwise an allocation failure can leave run() waiting forever.
            const OWKByteSlice empty{nullptr, 0};
            const OWKWidgetEvent event{
                kind,
                empty,
                empty,
                empty,
                empty,
                empty,
                OWK_WIDGET_SIZE_UNKNOWN,
                0,
                nullptr,
                nullptr
            };
            callbacks_.on_event(callbacks_.context, &event);
            return;
        }
        auto owner = new (std::nothrow) EventOwner{
            std::move(widget_id),
            std::move(definition_id),
            std::move(custom_state),
            std::move(action_verb),
            std::move(action_data)
        };
        if (owner == nullptr) {
            diagnostic(OWK_STATUS_INTERNAL_FAILURE, "Unable to allocate a provider event.");
            return;
        }
        OWKWidgetEvent event{
            kind,
            slice(owner->widget_id),
            slice(owner->definition_id),
            slice(owner->custom_state),
            slice(owner->action_verb),
            slice(owner->action_data),
            size,
            is_active ? 1 : 0,
            owner,
            release_event_owner
        };
        callbacks_.on_event(callbacks_.context, &event);
    }

    void diagnostic(int32_t code, std::string message) noexcept {
        if (callbacks_.on_diagnostic == nullptr) {
            return;
        }
        auto owner = new (std::nothrow) ResultOwner{std::move(message)};
        if (owner == nullptr) {
            return;
        }
        OWKOwnedBytes bytes{
            slice(owner->value),
            owner,
            release_result_owner
        };
        callbacks_.on_diagnostic(callbacks_.context, code, bytes);
    }

    OWKResult request_shutdown() noexcept {
        const auto suspended = begin_shutdown();
        if (FAILED(suspended)) {
            return failure(
                OWK_STATUS_COM_FAILURE,
                "COM class objects could not be suspended during shutdown."
            );
        }
        CoAddRefServerProcess();
        const auto remaining_references = CoReleaseServerProcess();
        if (remaining_references == 0) {
            emit_shutdown_if_needed();
        }
        return success();
    }

    void module_released() noexcept {
        const auto suspended = begin_shutdown();
        if (FAILED(suspended)) {
            diagnostic(
                OWK_STATUS_COM_FAILURE,
                "COM class objects could not be suspended after the module was released."
            );
            return;
        }
        emit_shutdown_if_needed();
    }

    OWKResult complete_shutdown() noexcept {
        {
            std::lock_guard lock(shutdown_mutex_);
            if (!shutdown_event_emitted_) {
                return failure(
                    OWK_STATUS_HOST_REJECTED,
                    "Shutdown cannot complete while COM provider objects are still retained."
                );
            }
            shutdown_requested_ = true;
        }
        if (!SetEvent(shutdown_completed_.get())) {
            return failure(
                OWK_STATUS_INTERNAL_FAILURE,
                "The provider shutdown event could not be signaled."
            );
        }
        return success();
    }

private:
    struct InstanceState {
        uint64_t generation = 0;
        bool deleted = false;
    };

    static GUID parse_class_id(std::string const& value) {
        GUID result{};
        auto wide = winrt::to_hstring(value);
        winrt::check_hresult(CLSIDFromString(wide.c_str(), &result));
        return result;
    }

    HRESULT begin_shutdown() noexcept {
        bool should_suspend = false;
        {
            std::lock_guard lock(shutdown_mutex_);
            shutdown_requested_ = true;
            if (!class_objects_suspended_) {
                class_objects_suspended_ = true;
                should_suspend = true;
            }
        }
        if (!should_suspend) {
            return S_OK;
        }
        const auto result = CoSuspendClassObjects();
        if (FAILED(result)) {
            std::lock_guard lock(shutdown_mutex_);
            class_objects_suspended_ = false;
        }
        return result;
    }

    HRESULT resume_class_objects_if_running() noexcept {
        std::lock_guard lock(shutdown_mutex_);
        if (shutdown_requested_) {
            return S_FALSE;
        }
        const auto result = CoResumeClassObjects();
        if (SUCCEEDED(result)) {
            class_objects_suspended_ = false;
        }
        return result;
    }

    void emit_shutdown_if_needed() noexcept {
        bool should_emit = false;
        {
            std::lock_guard lock(shutdown_mutex_);
            if (!shutdown_event_emitted_) {
                shutdown_event_emitted_ = true;
                should_emit = true;
            }
        }
        if (should_emit) {
            emit(OWK_EVENT_SHUTDOWN_REQUESTED);
        }
    }

    OWKResult enqueue_and_wait(std::function<OWKResult()> operation) {
        auto promise = std::make_shared<std::promise<OWKResult>>();
        auto future = promise->get_future();
        {
            std::lock_guard lock(operation_mutex_);
            if (stop_operations_) {
                return failure(OWK_STATUS_SHUTTING_DOWN, "The provider is shutting down.");
            }
            operations_.push_back(
                [operation = std::move(operation), promise](HRESULT apartment_result) mutable {
                    if (FAILED(apartment_result)) {
                        promise->set_value(
                            failure(
                                OWK_STATUS_COM_FAILURE,
                                "The provider operation thread could not initialize the Windows Runtime."
                            )
                        );
                        return;
                    }
                    promise->set_value(operation());
                }
            );
        }
        operation_condition_.notify_one();
        return future.get();
    }

    void process_operations() noexcept {
        const auto initialized = RoInitialize(RO_INIT_MULTITHREADED);
        while (true) {
            std::function<void(HRESULT)> operation;
            {
                std::unique_lock lock(operation_mutex_);
                operation_condition_.wait(lock, [this] {
                    return stop_operations_ || !operations_.empty();
                });
                if (stop_operations_ && operations_.empty()) {
                    break;
                }
                operation = std::move(operations_.front());
                operations_.pop_front();
            }
            operation(initialized);
        }
        if (SUCCEEDED(initialized)) {
            RoUninitialize();
        }
    }

    OWKCallbacks callbacks_{};
    GUID class_id_{};
    winrt::handle shutdown_completed_;

    std::mutex instance_mutex_;
    std::unordered_map<std::string, InstanceState> instances_;

    std::mutex operation_mutex_;
    std::condition_variable operation_condition_;
    std::deque<std::function<void(HRESULT)>> operations_;
    bool stop_operations_ = false;
    std::thread operation_thread_;

    std::mutex shutdown_mutex_;
    bool shutdown_requested_ = false;
    bool class_objects_suspended_ = false;
    bool shutdown_event_emitted_ = false;
};

std::mutex module_state_mutex;
std::weak_ptr<BridgeState> module_state;

struct WidgetProvider :
    winrt::implements<WidgetProvider, providers::IWidgetProvider> {
    explicit WidgetProvider(std::shared_ptr<BridgeState> state)
        : state_(std::move(state)) {}

    void CreateWidget(providers::WidgetContext const& context) {
        auto widget_id = winrt::to_string(context.Id());
        state_->host_created(widget_id);
        state_->emit(
            OWK_EVENT_CREATE,
            std::move(widget_id),
            winrt::to_string(context.DefinitionId()),
            {},
            {},
            {},
            widget_size(context),
            context.IsActive()
        );
    }

    void DeleteWidget(
        winrt::hstring const& widget_id,
        winrt::hstring const& custom_state
    ) {
        auto copied_id = winrt::to_string(widget_id);
        state_->host_deleted(copied_id);
        state_->emit(
            OWK_EVENT_DELETE,
            std::move(copied_id),
            {},
            winrt::to_string(custom_state)
        );
    }

    void Activate(providers::WidgetContext const& context) {
        state_->emit(
            OWK_EVENT_ACTIVATE,
            winrt::to_string(context.Id()),
            winrt::to_string(context.DefinitionId()),
            {},
            {},
            {},
            widget_size(context),
            true
        );
    }

    void Deactivate(winrt::hstring const& widget_id) {
        state_->emit(OWK_EVENT_DEACTIVATE, winrt::to_string(widget_id));
    }

    void OnWidgetContextChanged(providers::WidgetContextChangedArgs const& args) {
        auto context = args.WidgetContext();
        state_->emit(
            OWK_EVENT_CONTEXT_CHANGED,
            winrt::to_string(context.Id()),
            winrt::to_string(context.DefinitionId()),
            {},
            {},
            {},
            widget_size(context),
            context.IsActive()
        );
    }

    void OnActionInvoked(providers::WidgetActionInvokedArgs const& args) {
        auto context = args.WidgetContext();
        state_->emit(
            OWK_EVENT_ACTION_INVOKED,
            winrt::to_string(context.Id()),
            winrt::to_string(context.DefinitionId()),
            winrt::to_string(args.CustomState()),
            winrt::to_string(args.Verb()),
            winrt::to_string(args.Data()),
            widget_size(context),
            context.IsActive()
        );
    }

private:
    std::shared_ptr<BridgeState> state_;
};

struct ProviderFactory :
    winrt::implements<ProviderFactory, IClassFactory, winrt::no_module_lock> {
    explicit ProviderFactory(std::shared_ptr<BridgeState> state)
        : state_(std::move(state)) {}

    HRESULT __stdcall CreateInstance(
        IUnknown* outer,
        GUID const& interface_id,
        void** result
    ) noexcept final {
        if (result == nullptr) {
            return E_POINTER;
        }
        *result = nullptr;
        if (outer != nullptr) {
            return CLASS_E_NOAGGREGATION;
        }
        try {
            return winrt::make<WidgetProvider>(state_).as(interface_id, result);
        } catch (...) {
            return winrt::to_hresult();
        }
    }

    HRESULT __stdcall LockServer(BOOL) noexcept final {
        // The Windows Widget Provider factory is intentionally no_module_lock.
        // Created provider objects participate in the custom process lock;
        // the class factory does not keep the local server alive by itself.
        return S_OK;
    }

private:
    std::shared_ptr<BridgeState> state_;
};

OWKResult BridgeState::run() {
    const auto initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(initialized)) {
        return failure(OWK_STATUS_COM_FAILURE, "COM initialization failed.");
    }
    DWORD cookie = 0;
    try {
        {
            std::lock_guard lock(module_state_mutex);
            module_state = shared_from_this();
        }
        auto factory = winrt::make<ProviderFactory>(shared_from_this());
        winrt::check_hresult(
            CoRegisterClassObject(
                class_id_,
                factory.get(),
                CLSCTX_LOCAL_SERVER,
                REGCLS_MULTIPLEUSE | REGCLS_SUSPENDED,
                &cookie
            )
        );
        // Restore every existing instance before the class object becomes
        // callable. This preserves a single lifecycle order in Swift: all
        // recovery events are queued before any host callback can be accepted.
        for (auto const& info : providers::WidgetManager::GetDefault().GetWidgetInfos()) {
            auto context = info.WidgetContext();
            auto widget_id = winrt::to_string(context.Id());
            host_created(widget_id);
            emit(
                OWK_EVENT_RECOVER,
                std::move(widget_id),
                winrt::to_string(context.DefinitionId()),
                winrt::to_string(info.CustomState()),
                {},
                {},
                widget_size(context),
                context.IsActive()
            );
        }

        const auto resumed = resume_class_objects_if_running();
        winrt::check_hresult(resumed);

        DWORD event_index = 0;
        HANDLE events[] = {shutdown_completed_.get()};
        winrt::check_hresult(
            CoWaitForMultipleObjects(
                CWMO_DISPATCH_CALLS | CWMO_DISPATCH_WINDOW_MESSAGES,
                INFINITE,
                1,
                events,
                &event_index
            )
        );
        CoRevokeClassObject(cookie);
        {
            std::lock_guard lock(module_state_mutex);
            module_state.reset();
        }
        if (SUCCEEDED(initialized)) {
            CoUninitialize();
        }
        return success();
    } catch (...) {
        auto result = current_exception();
        if (cookie != 0) {
            const auto suspended = begin_shutdown();
            if (FAILED(suspended)) {
                diagnostic(
                    OWK_STATUS_COM_FAILURE,
                    "COM class objects could not be suspended after provider startup failed."
                );
            }
            CoRevokeClassObject(cookie);
            CoAddRefServerProcess();
            const auto remaining_references = CoReleaseServerProcess();
            if (remaining_references == 0) {
                emit_shutdown_if_needed();
            }
            DWORD event_index = 0;
            HANDLE events[] = {shutdown_completed_.get()};
            const auto wait_result = CoWaitForMultipleObjects(
                CWMO_DISPATCH_CALLS | CWMO_DISPATCH_WINDOW_MESSAGES,
                INFINITE,
                1,
                events,
                &event_index
            );
            if (FAILED(wait_result)) {
                diagnostic(
                    OWK_STATUS_COM_FAILURE,
                    "The provider could not finish its failure-path shutdown wait."
                );
            }
        }
        {
            std::lock_guard lock(module_state_mutex);
            module_state.reset();
        }
        if (SUCCEEDED(initialized)) {
            CoUninitialize();
        }
        return result;
    }
}

} // namespace

void open_widget_module_released() noexcept {
    std::shared_ptr<BridgeState> state;
    {
        std::lock_guard lock(module_state_mutex);
        state = module_state.lock();
    }
    if (state) {
        state->module_released();
    }
}

struct OWKProviderHandle {
    std::shared_ptr<BridgeState> state;
};

extern "C" {

OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_create(
    OWKProviderConfiguration const* configuration,
    OWKProviderHandle** handle
) {
    if (configuration == nullptr || handle == nullptr
        || configuration->callbacks.on_event == nullptr) {
        return failure(OWK_STATUS_INVALID_ARGUMENT, "Invalid provider configuration.");
    }
    *handle = nullptr;
    try {
        auto value = std::make_unique<OWKProviderHandle>();
        value->state = std::make_shared<BridgeState>(*configuration);
        *handle = value.release();
        return success();
    } catch (...) {
        return current_exception();
    }
}

OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_run(OWKProviderHandle* handle) {
    if (handle == nullptr) return failure(OWK_STATUS_INVALID_ARGUMENT, "Provider handle is null.");
    try { return handle->state->run(); } catch (...) { return current_exception(); }
}

OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_request_shutdown(OWKProviderHandle* handle) {
    if (handle == nullptr) return failure(OWK_STATUS_INVALID_ARGUMENT, "Provider handle is null.");
    const auto initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
        return failure(
            OWK_STATUS_COM_FAILURE,
            "COM initialization failed while requesting provider shutdown."
        );
    }
    auto result = handle->state->request_shutdown();
    if (SUCCEEDED(initialized)) {
        CoUninitialize();
    }
    return result;
}

OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_complete_shutdown(OWKProviderHandle* handle) {
    if (handle == nullptr) return failure(OWK_STATUS_INVALID_ARGUMENT, "Provider handle is null.");
    return handle->state->complete_shutdown();
}

OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_invalidate(
    OWKProviderHandle* handle,
    OWKByteSlice widget_id,
    uint64_t generation
) {
    if (handle == nullptr) return failure(OWK_STATUS_INVALID_ARGUMENT, "Provider handle is null.");
    try { return handle->state->invalidate(copy_slice(widget_id), generation); }
    catch (...) { return current_exception(); }
}

OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_update(
    OWKProviderHandle* handle,
    OWKByteSlice widget_id,
    uint64_t generation,
    OWKByteSlice template_json,
    OWKByteSlice data_json,
    OWKByteSlice custom_state
) {
    if (handle == nullptr) return failure(OWK_STATUS_INVALID_ARGUMENT, "Provider handle is null.");
    try {
        std::optional<std::string> template_value;
        if (template_json.count > 0) {
            template_value = copy_slice(template_json);
        }
        return handle->state->update(
            copy_slice(widget_id),
            generation,
            std::move(template_value),
            copy_slice(data_json),
            copy_slice(custom_state)
        );
    } catch (...) { return current_exception(); }
}

OWK_PROVIDER_API OWKResult OWK_CALL owk_provider_remove(
    OWKProviderHandle* handle,
    OWKByteSlice widget_id,
    uint64_t generation
) {
    if (handle == nullptr) return failure(OWK_STATUS_INVALID_ARGUMENT, "Provider handle is null.");
    try { return handle->state->remove(copy_slice(widget_id), generation); }
    catch (...) { return current_exception(); }
}

OWK_PROVIDER_API void OWK_CALL owk_provider_destroy(OWKProviderHandle* handle) {
    delete handle;
}

} // extern "C"
