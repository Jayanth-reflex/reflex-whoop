import Foundation

/// Pure statistics helpers, no dependencies, no database access. Everything here
/// is unit-testable against a known answer — see the design doc's "never
/// fabricate" rule: every function returns `nil`/`.insufficient` rather than a
/// number when there isn't enough data to say something real.
enum Stats {
    static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample standard deviation (n-1 denominator) — the right choice here since
    /// every baseline window is itself a sample of a longer, ongoing history, not
    /// the whole population.
    static func stddev(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let variance = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)
        return variance.squareRoot()
    }

    static func zScore(value: Double, mean: Double, stddev: Double) -> Double? {
        guard stddev > 0 else { return nil }
        return (value - mean) / stddev
    }

    /// Spearman's rank correlation: Pearson correlation of the ranks, which is
    /// what makes it robust to the outliers and non-linearity a single person's
    /// physiological data is full of. Ties get the average of their tied ranks.
    static func spearmanRho(_ xs: [Double], _ ys: [Double]) -> (rho: Double, n: Int)? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let rankX = ranks(of: xs)
        let rankY = ranks(of: ys)
        guard let rho = pearson(rankX, rankY) else { return nil }
        return (rho, xs.count)
    }

    private static func ranks(of xs: [Double]) -> [Double] {
        let sortedIndices = xs.indices.sorted { xs[$0] < xs[$1] }
        var ranks = [Double](repeating: 0, count: xs.count)
        var i = 0
        while i < sortedIndices.count {
            var j = i
            while j + 1 < sortedIndices.count, xs[sortedIndices[j + 1]] == xs[sortedIndices[i]] {
                j += 1
            }
            // Tied values share the average of the rank positions they span.
            let averageRank = Double(i + j) / 2.0 + 1.0
            for k in i...j {
                ranks[sortedIndices[k]] = averageRank
            }
            i = j + 1
        }
        return ranks
    }

    private static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2,
              let mx = mean(xs), let my = mean(ys) else { return nil }
        var num = 0.0, denomX = 0.0, denomY = 0.0
        for i in xs.indices {
            let dx = xs[i] - mx, dy = ys[i] - my
            num += dx * dy
            denomX += dx * dx
            denomY += dy * dy
        }
        guard denomX > 0, denomY > 0 else { return nil }
        return num / (denomX.squareRoot() * denomY.squareRoot())
    }

    /// Two-tailed p-value for a correlation coefficient, via the standard
    /// t-approximation: t = rho * sqrt((n-2)/(1-rho^2)), df = n-2. Exact for
    /// Pearson's r under normality; a widely-used, honest approximation for
    /// Spearman's rho at the sample sizes a personal WHOOP history produces.
    static func pValue(rho: Double, n: Int) -> Double? {
        guard n > 2, abs(rho) < 1 else { return rho == 0 ? 1.0 : 0.0 }
        let df = Double(n - 2)
        let t = rho * (df / (1 - rho * rho)).squareRoot()
        return 2 * (1 - studentTCDF(abs(t), df: df))
    }

    /// CDF of Student's t distribution, via the regularized incomplete beta
    /// function — the standard closed-form relationship, not a lookup table.
    private static func studentTCDF(_ t: Double, df: Double) -> Double {
        let x = df / (df + t * t)
        let ibeta = regularizedIncompleteBeta(x, df / 2, 0.5)
        return 1 - 0.5 * ibeta
    }

    /// Regularized incomplete beta function I_x(a, b) via the continued-fraction
    /// method (Numerical Recipes §6.4) — the standard way to evaluate this
    /// without a stats library.
    private static func regularizedIncompleteBeta(_ x: Double, _ a: Double, _ b: Double) -> Double {
        guard x > 0, x < 1 else { return x <= 0 ? 0 : 1 }
        let logBeta = lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log(1 - x)
        let front = exp(logBeta)
        if x < (a + 1) / (a + b + 2) {
            return front * betaContinuedFraction(x, a, b) / a
        } else {
            return 1 - front * betaContinuedFraction(1 - x, b, a) / b
        }
    }

    private static func betaContinuedFraction(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let maxIterations = 200
        let epsilon = 1e-10
        let fpmin = 1e-300

        let qab = a + b, qap = a + 1, qam = a - 1
        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < fpmin { d = fpmin }
        d = 1 / d
        var h = d

        for m in 1...maxIterations {
            let m2 = Double(2 * m)
            var aa = Double(m) * (b - Double(m)) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d
            if abs(d) < fpmin { d = fpmin }
            c = 1 + aa / c
            if abs(c) < fpmin { c = fpmin }
            d = 1 / d
            h *= d * c

            aa = -(a + Double(m)) * (qab + Double(m)) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d
            if abs(d) < fpmin { d = fpmin }
            c = 1 + aa / c
            if abs(c) < fpmin { c = fpmin }
            d = 1 / d
            let delta = d * c
            h *= delta

            if abs(delta - 1) < epsilon { break }
        }
        return h
    }

    /// Benjamini-Hochberg correction: controls the false discovery rate across a
    /// whole batch of correlations tested together. Necessary here specifically
    /// because CorrelationEngine tests ~9 predictors against one outcome on one
    /// person's data — without this, roughly one of them would look "significant"
    /// by chance alone even if nothing real were going on.
    static func benjaminiHochberg(_ pValues: [Double]) -> [Double] {
        let n = pValues.count
        guard n > 0 else { return [] }
        let order = pValues.indices.sorted { pValues[$0] < pValues[$1] }
        var adjusted = [Double](repeating: 0, count: n)
        var runningMin = 1.0
        for rank in stride(from: n - 1, through: 0, by: -1) {
            let i = order[rank]
            let candidate = pValues[i] * Double(n) / Double(rank + 1)
            runningMin = min(runningMin, candidate)
            adjusted[i] = min(runningMin, 1.0)
        }
        return adjusted
    }

    enum Strength: String {
        case strong, moderate, weak, insufficient
    }

    /// n < 30 is called out explicitly in the design doc: below that, a
    /// correlation on one person's noisy day-to-day data is not trustworthy
    /// regardless of how large rho looks.
    static let minimumDaysForStrength = 30

    static func strength(rho: Double, n: Int) -> Strength {
        guard n >= minimumDaysForStrength else { return .insufficient }
        switch abs(rho) {
        case 0.5...: return .strong
        case 0.3..<0.5: return .moderate
        default: return .weak
        }
    }
}
