import SwiftUI
import UIKit

/// UIPageViewController-backed paging container. Replaces SwiftUI's
/// `TabView(.page)` because that style's interactive/programmatic animation
/// isn't consistent across child content — specifically, a `Form`-backed
/// child (AppSettingsView) would snap into place instantly while
/// `ScrollView` / `List`-backed children (Dashboard, Query Log) slid
/// smoothly. Routing through `UIPageViewController` gives every tab the
/// same native spring slide on both swipe and tap.
///
/// - `selectedIndex`: two-way bound tab index. Writes from the bottom bar
///   drive programmatic navigation; user swipes drive writes back.
/// - `pageCount`: total number of tabs.
/// - `pageContent`: returns the SwiftUI view for a given tab index. Called
///   on first materialization and again whenever SwiftUI re-evaluates the
///   parent (so the cached host controllers pick up state changes, e.g.
///   when `activeSite` flips and `dashboardVM` / `queryLogVM` change).
struct PagingTabContainer: UIViewControllerRepresentable {
    @Binding var selectedIndex: Int
    let pageCount: Int
    let pageContent: (Int) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        if let first = context.coordinator.hostingController(for: selectedIndex) {
            pvc.setViewControllers([first], direction: .forward, animated: false)
        }
        return pvc
    }

    func updateUIViewController(_ uiVC: UIPageViewController, context: Context) {
        // Keep a fresh reference to the representable (its `@Binding` and
        // closure may capture newer state on every re-evaluation).
        context.coordinator.parent = self

        // Push current SwiftUI state into every cached host so existing
        // pages re-render when upstream `@Observable` values change (e.g.
        // the active site flips under us).
        context.coordinator.refreshAllPages()

        // If something external set `selectedIndex` to a tab other than the
        // one currently on screen (typical: bottom-bar tap), navigate there
        // with UIKit's native animated slide. Swipe-driven changes route
        // back through `didFinishAnimating` and won't re-enter here because
        // `currentIdx == selectedIndex` by then.
        guard let currentVC = uiVC.viewControllers?.first,
              let currentIdx = context.coordinator.index(of: currentVC),
              currentIdx != selectedIndex,
              let targetVC = context.coordinator.hostingController(for: selectedIndex)
        else { return }
        let direction: UIPageViewController.NavigationDirection =
            selectedIndex > currentIdx ? .forward : .reverse
        uiVC.setViewControllers([targetVC], direction: direction, animated: true)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagingTabContainer

        /// Cache of materialized host controllers keyed by tab index.
        /// UIPageViewController identifies neighbours by `===` so the
        /// controllers have to be stable across data-source callbacks —
        /// creating a fresh UIHostingController each lookup would break the
        /// before/after resolution and prevent the swipe gesture from
        /// finding adjacent pages.
        private var cache: [Int: UIHostingController<AnyView>] = [:]

        init(_ parent: PagingTabContainer) {
            self.parent = parent
        }

        func hostingController(for index: Int) -> UIHostingController<AnyView>? {
            guard (0..<parent.pageCount).contains(index) else { return nil }
            if let cached = cache[index] {
                cached.rootView = parent.pageContent(index)
                return cached
            }
            let hc = UIHostingController(rootView: parent.pageContent(index))
            // Transparent background so the SwiftUI content controls the
            // visual (tab backgrounds, NavigationStack bars, etc.).
            hc.view.backgroundColor = .clear
            cache[index] = hc
            return hc
        }

        func refreshAllPages() {
            for (idx, hc) in cache {
                hc.rootView = parent.pageContent(idx)
            }
        }

        func index(of viewController: UIViewController) -> Int? {
            cache.first(where: { $0.value === viewController })?.key
        }

        // MARK: UIPageViewControllerDataSource

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerBefore vc: UIViewController
        ) -> UIViewController? {
            guard let idx = index(of: vc) else { return nil }
            return hostingController(for: idx - 1)
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerAfter vc: UIViewController
        ) -> UIViewController? {
            guard let idx = index(of: vc) else { return nil }
            return hostingController(for: idx + 1)
        }

        // MARK: UIPageViewControllerDelegate

        func pageViewController(
            _ pvc: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            // Only sync the binding back when a swipe actually committed —
            // a cancelled drag (completed == false) should leave the tab
            // selection where the user left it, not reset it.
            guard completed,
                  let current = pvc.viewControllers?.first,
                  let idx = index(of: current),
                  parent.selectedIndex != idx
            else { return }
            // Defer to next tick so SwiftUI isn't mid-render when we write
            // to the binding; otherwise the "Modifying state during view
            // update" warning fires in debug builds.
            DispatchQueue.main.async { [parent] in
                parent.selectedIndex = idx
            }
        }
    }
}
