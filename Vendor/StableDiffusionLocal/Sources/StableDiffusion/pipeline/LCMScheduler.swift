// For licensing see accompanying LICENSE.md file.
// Based on Hugging Face Diffusers LCMScheduler (Apache-2.0).

import CoreML

/// Latent Consistency Model scheduler for one-to-eight step inference.
///
/// This follows the boundary-condition and stochastic multistep update in
/// Diffusers `scheduling_lcm.py`. LCM-distilled UNets must use their distilled
/// timestep schedule rather than a regular PNDM or DPM-Solver schedule.
@available(iOS 16.2, macOS 13.1, *)
public final class LCMScheduler: Scheduler {
    public let trainStepCount: Int
    public let inferenceStepCount: Int
    public let betas: [Float]
    public let alphas: [Float]
    public let alphasCumProd: [Float]
    public let timeSteps: [Int]

    public private(set) var modelOutputs: [MLShapedArray<Float32>] = []

    private let originalInferenceSteps: Int
    private let timestepScaling: Float
    private let sigmaData: Float = 0.5
    private var activeTimeSteps: [Int]
    private var random: any RandomSource

    public init(
        stepCount: Int = 8,
        trainStepCount: Int = 1000,
        originalInferenceSteps: Int = 50,
        betaSchedule: BetaSchedule = .scaledLinear,
        betaStart: Float = 0.00085,
        betaEnd: Float = 0.012,
        timestepScaling: Float = 10,
        seed: UInt32 = 0,
        rngType: StableDiffusionRNG = .numpyRNG
    ) {
        self.trainStepCount = trainStepCount
        self.inferenceStepCount = max(1, min(stepCount, originalInferenceSteps))
        self.originalInferenceSteps = originalInferenceSteps
        self.timestepScaling = timestepScaling

        switch betaSchedule {
        case .linear:
            self.betas = linspace(betaStart, betaEnd, trainStepCount)
        case .scaledLinear:
            self.betas = linspace(sqrt(betaStart), sqrt(betaEnd), trainStepCount).map { $0 * $0 }
        }
        self.alphas = betas.map { 1 - $0 }
        var cumulative = alphas
        for index in 1..<cumulative.count {
            cumulative[index] *= cumulative[index - 1]
        }
        self.alphasCumProd = cumulative

        self.timeSteps = Self.makeTimeSteps(
            inferenceStepCount: self.inferenceStepCount,
            trainStepCount: trainStepCount,
            originalInferenceSteps: originalInferenceSteps
        )
        self.activeTimeSteps = self.timeSteps

        switch rngType {
        case .numpyRNG:
            self.random = NumPyRandomSource(seed: seed)
        case .torchRNG:
            self.random = TorchRandomSource(seed: seed)
        case .nvidiaRNG:
            self.random = NvRandomSource(seed: seed)
        }
    }

    private static func makeTimeSteps(
        inferenceStepCount: Int,
        trainStepCount: Int,
        originalInferenceSteps: Int
    ) -> [Int] {
        let skippingStep = trainStepCount / originalInferenceSteps
        let original = (1...originalInferenceSteps).map { $0 * skippingStep - 1 }.reversed()
        let schedule = Array(original)
        let interval = Double(schedule.count) / Double(inferenceStepCount)
        return (0..<inferenceStepCount).map { index in
            schedule[min(Int(floor(Double(index) * interval)), schedule.count - 1)]
        }
    }

    /// Uses the same RNG stream for initial latent noise and per-step LCM noise.
    func initialNoiseSample(shape: [Int]) -> MLShapedArray<Float32> {
        MLShapedArray<Float32>(
            converting: random.normalShapedArray(shape, mean: 0, stdev: 1)
        )
    }

    public func calculateTimesteps(strength: Float?) -> [Int] {
        guard let strength else {
            activeTimeSteps = timeSteps
            return activeTimeSteps
        }
        let usedStepCount = max(1, min(
            inferenceStepCount,
            Int(Float(inferenceStepCount) * max(0, min(strength, 1)))
        ))
        activeTimeSteps = Array(timeSteps.suffix(usedStepCount))
        return activeTimeSteps
    }

    public func addNoise(
        originalSample: MLShapedArray<Float32>,
        noise: [MLShapedArray<Float32>],
        strength: Float
    ) -> [MLShapedArray<Float32>] {
        let usedStepCount = max(1, min(
            inferenceStepCount,
            Int(Float(inferenceStepCount) * max(0, min(strength, 1)))
        ))
        let firstTimeStep = timeSteps[timeSteps.count - usedStepCount]
        let alphaProduct = alphasCumProd[firstTimeStep]
        return noise.map {
            weightedSum(
                [Double(sqrt(alphaProduct)), Double(sqrt(1 - alphaProduct))],
                [originalSample, $0]
            )
        }
    }

    public func step(
        output: MLShapedArray<Float32>,
        timeStep: Int,
        sample: MLShapedArray<Float32>
    ) -> MLShapedArray<Float32> {
        let index = activeTimeSteps.firstIndex(of: timeStep) ?? max(activeTimeSteps.count - 1, 0)
        let previousTimeStep = index + 1 < activeTimeSteps.count
            ? activeTimeSteps[index + 1]
            : timeStep

        let alphaProduct = alphasCumProd[timeStep]
        let betaProduct = 1 - alphaProduct
        let predictedOriginal = weightedSum(
            [Double(1 / sqrt(alphaProduct)), Double(-sqrt(betaProduct) / sqrt(alphaProduct))],
            [sample, output]
        )

        let scaledTimeStep = Float(timeStep) * timestepScaling
        let denominator = scaledTimeStep * scaledTimeStep + sigmaData * sigmaData
        let cSkip = sigmaData * sigmaData / denominator
        let cOut = scaledTimeStep / sqrt(denominator)
        let denoised = weightedSum(
            [Double(cOut), Double(cSkip)],
            [predictedOriginal, sample]
        )
        modelOutputs = [denoised]

        guard index != activeTimeSteps.count - 1 else {
            return denoised
        }

        let previousAlphaProduct = alphasCumProd[previousTimeStep]
        let noise = MLShapedArray<Float32>(
            converting: random.normalShapedArray(output.shape, mean: 0, stdev: 1)
        )
        return weightedSum(
            [Double(sqrt(previousAlphaProduct)), Double(sqrt(1 - previousAlphaProduct))],
            [denoised, noise]
        )
    }
}
