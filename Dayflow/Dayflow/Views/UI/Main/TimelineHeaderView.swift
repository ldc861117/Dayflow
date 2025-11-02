//
//  TimelineHeaderView.swift
//  Dayflow
//
//  Header showing date navigation controls and recording toggle
//

import SwiftUI
import AppKit

struct TimelineHeaderView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var appState: AppState
    
    private static let maxDateTitleWidth: CGFloat = {
        let referenceText = "Today, Sep 30"
        let font = NSFont(name: "InstrumentSerif-Regular", size: 36) ?? NSFont.systemFont(ofSize: 36)
        let width = referenceText.size(withAttributes: [.font: font]).width
        return ceil(width) + 4
    }()
    
    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 16) {
                Button(action: {
                    viewModel.openDatePicker()
                }) {
                    Text(formatDateForDisplay(viewModel.selectedDate))
                        .font(.custom("InstrumentSerif-Regular", size: 36))
                        .foregroundColor(Color.black)
                        .frame(width: Self.maxDateTitleWidth, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
                
                HStack(spacing: 3) {
                    Button(action: {
                        viewModel.navigatePrevious()
                    }) {
                        Image("CalendarLeftButton")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        viewModel.navigateNext()
                    }) {
                        Image("CalendarRightButton")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel.canNavigateForward() == false)
                }
            }
            .offset(x: viewModel.timelineOffset)
            .opacity(viewModel.timelineOpacity)
            
            Spacer()
            
            HStack(spacing: 4) {
                Text("Record")
                    .font(Font.custom("Nunito", size: 12).weight(.medium))
                    .foregroundColor(Color(red: 0.62, green: 0.44, blue: 0.36))
                
                Toggle("Record", isOn: $appState.isRecording)
                    .labelsHidden()
                    .toggleStyle(SunriseGlassPillToggleStyle())
                    .scaleEffect(0.7)
                    .accessibilityLabel(Text("Recording"))
            }
        }
        .padding(.horizontal, 10)
    }
}
