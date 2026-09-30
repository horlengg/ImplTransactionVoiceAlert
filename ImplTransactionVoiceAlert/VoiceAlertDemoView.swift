//
//  VoiceAlertDemoView.swift
//  ImplTransactionVoiceAlert
//
//  Created by Houleng.LY on 29/9/26.
//

import SwiftUI
import AVFoundation


// MARK: - Home screen

struct VoiceAlertDemoView: View {

    @StateObject private var viewModel = VoiceAlertDemoViewModel()
    @FocusState private var amountFocused: Bool

    private let quickAmounts = ["1", "12.50", "250", "1250000"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    amountCard
                    optionsCard
                    playButton

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !viewModel.tokens.isEmpty {
                        clipsCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Paysound")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.amount) { _, newValue in
                let cleaned = VoiceAlertDemoViewModel.sanitizeAmount(newValue)
                if cleaned != newValue { viewModel.amount = cleaned }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false }
                }
            }
        }
    }

    // MARK: Sections

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Amount")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                TextField("0.00", text: $viewModel.amount)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .minimumScaleFactor(0.5)

                if !viewModel.amount.isEmpty {
                    Button {
                        viewModel.amount = ""
                        amountFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Text(String(describing: viewModel.currency))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = true }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(quickAmounts, id: \.self) { value in
                        Button(value) { viewModel.amount = value }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var optionsCard: some View {
        VStack(spacing: 16) {
            Picker("Currency", selection: $viewModel.currency) {
                Text("USD").tag(SpeechCurrency.USD)
                Text("KHR").tag(SpeechCurrency.KHR)
            }
            .pickerStyle(.segmented)

            Picker("Language", selection: $viewModel.language) {
                Text("English").tag(SpeechLanguage.english)
                Text("Khmer").tag(SpeechLanguage.khmer)
            }
            .pickerStyle(.segmented)

            Picker("Voice", selection: $viewModel.voice) {
                ForEach(Array(SpeechVoice.allCases), id: \.self) { voice in
                    Text(voice.name.capitalized).tag(voice)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var playButton: some View {
        Button {
            amountFocused = false
            viewModel.isPlaying ? viewModel.stop() : viewModel.play()
        } label: {
            HStack {
                if viewModel.isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                }
                Text(viewModel.isPlaying ? "Stop" : "Play sound")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.isBusy || viewModel.amount.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Shows the clip sequence, which is the core idea behind the notification sound.
    private var clipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clip sequence")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(viewModel.tokens.enumerated()), id: \.offset) { _, token in
                    Text(token)
                        .font(.footnote.monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
