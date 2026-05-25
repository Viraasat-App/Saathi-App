/// Determines what happens after OTP is verified in the auth flow.
///
/// - [register]: new user → `/profile` to collect personal details, then `/chat`.
/// - [login]: existing user → `/chat` directly (skips profile setup).
enum AuthFlowMode { register, login }
