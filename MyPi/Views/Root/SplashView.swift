import SwiftUI

/// Brief brand splash shown at the root of the view hierarchy on first
/// launch of each session. Held for ~2 seconds then faded out by
/// `ContentView` so the main UI takes over.
///
/// The background color matches the `UILaunchScreen` asset so there's no
/// visible boundary between the OS-level launch screen and this view —
/// the logo appears to animate in on top of the same canvas.
struct SplashView: View {
    private let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    @State private var logoShown = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("AppLogo")
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
                    .scaleEffect(logoShown ? 1 : 0.85)
                    .opacity(logoShown ? 1 : 0)

                VStack(spacing: 6) {
                    Text("MyPi Companion")
                        .font(.title2).bold()
                    Text("v\(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .opacity(logoShown ? 1 : 0)
                .offset(y: logoShown ? 0 : 8)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                logoShown = true
            }
        }
    }
}
