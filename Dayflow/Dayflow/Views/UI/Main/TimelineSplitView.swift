//
//  TimelineSplitView.swift
//  Dayflow
//
//  Main split view showing timeline and activity detail panel
//

import SwiftUI

struct TimelineSplitView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var appState: AppState
    @EnvironmentObject private var categoryStore: CategoryStore
    
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    TimelineHeaderView(viewModel: viewModel, appState: appState)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        TabFilterBar(
                            categories: categoryStore.editableCategories,
                            idleCategory: categoryStore.idleCategory,
                            onManageCategories: { viewModel.showCategoryEditor = true }
                        )
                        .padding(.leading, 10)
                        .opacity(viewModel.contentOpacity)
                        
                        CanvasTimelineDataView(
                            selectedDate: $viewModel.selectedDate,
                            selectedActivity: $viewModel.selectedActivity,
                            scrollToNowTick: $viewModel.scrollToNowTick,
                            hasAnyActivities: $viewModel.hasAnyActivities
                        )
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                        .environmentObject(categoryStore)
                        .opacity(viewModel.contentOpacity)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 15)
                .padding(.bottom, 15)
                .padding(.leading, 15)
                .padding(.trailing, 5)
                
                Rectangle()
                    .fill(Color(hex: "ECECEC") ?? Color.gray)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                
                ZStack(alignment: .topLeading) {
                    Color.white.opacity(0.7)
                    
                    ActivityDetailPanel(
                        activity: viewModel.selectedActivity,
                        maxHeight: geo.size.height,
                        scrollSummary: true,
                        hasAnyActivities: viewModel.hasAnyActivities
                    )
                    .opacity(viewModel.contentOpacity)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 0,
                            bottomLeading: 0, bottomTrailing: 8, topTrailing: 8
                        )
                    )
                )
                .contentShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 0,
                            bottomLeading: 0, bottomTrailing: 8, topTrailing: 8
                        )
                    )
                )
                .frame(minWidth: 195, idealWidth: 285, maxWidth: 315, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

struct TabFilterBar: View {
    let categories: [TimelineCategory]
    let idleCategory: TimelineCategory?
    let onManageCategories: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(categories) { category in
                        CategoryChip(category: category, isIdle: false)
                    }

                    if let idleCategory {
                        CategoryChip(category: idleCategory, isIdle: true)
                    }

                    Color.clear.frame(width: 8)
                }
                .padding(.leading, 1)
                .padding(.trailing, 34)
            }
            .frame(height: 26)

            HStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    gradient: Gradient(colors: [Color.clear, Color(hex: "FFF8F1") ?? Color.white]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 40)
                .allowsHitTesting(false)

                Color(hex: "FFF8F1")
                    .frame(width: 26)
                    .allowsHitTesting(false)
            }

            Button(action: onManageCategories) {
                Image("CategoryEditButton")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(height: 26)
    }

    struct CategoryChip: View {
        let category: TimelineCategory
        let isIdle: Bool

        var body: some View {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: category.colorHex) ?? .blue)
                    .frame(width: 10, height: 10)

                Text(category.name)
                    .font(Font.custom("Nunito", size: 13).weight(.medium))
                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(height: 26)
            .background(.white.opacity(0.76))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .inset(by: 0.25)
                    .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.5)
            )
        }
    }
}
