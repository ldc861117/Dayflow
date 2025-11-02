//
//  TimelineSidebar.swift
//  Dayflow
//
//  Sidebar with logo and navigation buttons for the main view
//

import SwiftUI

struct TimelineSidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            LogoBadgeView(imageName: "DayflowLogoMainApp", size: 36)
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .scaleEffect(viewModel.logoScale)
                .opacity(viewModel.logoOpacity)
            
            Spacer(minLength: 0)
            
            VStack {
                Spacer()
                SidebarView(selectedIcon: $viewModel.selectedIcon)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: viewModel.sidebarOffset)
                    .opacity(viewModel.sidebarOpacity)
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .frame(width: 100)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: .infinity)
        .layoutPriority(1)
    }
}

enum SidebarIcon: CaseIterable {
    case timeline
    case dashboard
    case journal
    case bug
    case settings

    var assetName: String? {
        switch self {
        case .timeline: return "TimelineIcon"
        case .dashboard: return "DashboardIcon"
        case .journal: return "JournalIcon"
        case .bug: return nil
        case .settings: return nil
        }
    }

    var systemNameFallback: String? {
        switch self {
        case .bug: return "exclamationmark.bubble"
        case .settings: return "gearshape"
        default: return nil
        }
    }
}

struct SidebarView: View {
    @Binding var selectedIcon: SidebarIcon
    
    var body: some View {
        VStack(alignment: .center, spacing: 10.501) {
            ForEach(SidebarIcon.allCases, id: \.self) { icon in
                SidebarIconButton(
                    icon: icon,
                    isSelected: selectedIcon == icon,
                    action: { selectedIcon = icon }
                )
                .frame(width: 40, height: 40)
            }
        }
    }
}

struct SidebarIconButton: View {
    let icon: SidebarIcon
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Image("IconBackground")
                        .resizable()
                        .interpolation(.high)
                        .renderingMode(.original)
                }

                if let asset = icon.assetName {
                    Image(asset)
                        .resizable()
                        .interpolation(.high)
                        .renderingMode(.template)
                        .foregroundColor(isSelected ? Color(hex: "F96E00") : Color(red: 0.6, green: 0.4, blue: 0.3))
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else if let sys = icon.systemNameFallback {
                    Image(systemName: sys)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? Color(hex: "F96E00") : Color(red: 0.6, green: 0.4, blue: 0.3))
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
}
