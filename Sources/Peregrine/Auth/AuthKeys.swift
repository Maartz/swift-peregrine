/// String-based assign keys for authentication state.
///
/// Uses string keys (not typed `AssignKey`) so values can be cleared on logout.
public enum AuthAssign {
    /// The currently authenticated user (type-erased).
    public static let currentUser = "_peregrine_current_user"

    /// The authenticated user's ID string.
    public static let currentUserID = "_peregrine_current_user_id"

    /// Auth context: `"session"` or `"api"`.
    public static let authContext = "_peregrine_auth_context"
}
