/// Generic view-state used by [BaseController]/[BaseView] to decide whether
/// to render content, a skeleton, an error screen, or an empty state —
/// independent of whatever domain-specific loading flags a controller
/// already exposes (those keep working unchanged).
enum BaseViewState { idle, loading, success, error, empty }
