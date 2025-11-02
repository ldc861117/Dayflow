//
//  MainView.swift
//  Dayflow
//
//  Timeline UI with transparent design
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var categoryStore: CategoryStore
    @StateObject private var viewModel: MainViewModel
    
    init() {
        _viewModel = StateObject(wrappedValue: MainViewModel(appState: AppState.shared))
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TimelineSidebarView(viewModel: viewModel)
            
            ZStack {
                switch viewModel.selectedIcon {
                case .settings:
                    SettingsView()
                        .padding(15)
                case .dashboard:
                    DashboardView()
                        .padding(15)
                case .journal:
                    JournalView()
                        .padding(15)
                case .bug:
                    BugReportView()
                        .padding(15)
                case .timeline:
                    TimelineSplitView(viewModel: viewModel, appState: appState)
                        .environmentObject(categoryStore)
                }
            }
            .padding(0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 0)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                        .blendMode(.destinationOut)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.22))
                }
                .compositingGroup()
            )
        }
        .padding([.top, .trailing, .bottom], 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .ignoresSafeArea()
        .sheet(isPresented: $viewModel.showDatePicker) {
            DatePickerSheet(
                selectedDate: Binding(
                    get: { viewModel.selectedDate },
                    set: { viewModel.navigateToDate($0, method: "picker") }
                ),
                isPresented: $viewModel.showDatePicker
            )
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .overlay {
            if viewModel.showCategoryEditor {
                ColorOrganizerRoot(
                    presentationStyle: .sheet,
                    onDismiss: { viewModel.showCategoryEditor = false },
                    completionButtonTitle: "Save",
                    showsTitles: true
                )
                .environmentObject(categoryStore)
            }
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
            
            HStack {
                Text("\(value)%")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geometry.size.width * CGFloat(value) / 100, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
    }
}
