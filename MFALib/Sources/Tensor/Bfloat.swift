//
//  Bfloat.swift
//  MetalFlashAttention
//
//  Created by Ivar Flakstad on 22/02/2024.
//

import Swift
import SwiftShims


@frozen
public struct BFloat {
    @usableFromInline @inline(__always)
    internal var _value: UInt16

    @_transparent
    public init(_ v: UInt16) {
        _value = v
    }
    
    @_transparent
    public init() {
        _value = BFloat.zero._value
    }
};

extension BFloat: CustomStringConvertible {
  /// A textual representation of the value.
  ///
  /// For any finite value, this property provides a string that can be
  /// converted back to an instance of `BFloat` without rounding errors.  That
  /// is, if `x` is an instance of `BFloat`, then `BFloat(x.description) ==
  /// x` is always true.  For any NaN value, the property's value is "nan", and
  /// for positive and negative infinity its value is "inf" and "-inf".
  public var description: String {
    Float(self).description
  }
}


extension BFloat: CustomDebugStringConvertible {
  /// A textual representation of the value, suitable for debugging.
  ///
  /// This property has the same value as the `description` property, except
  /// that NaN values are printed in an extended format.
  public var debugDescription: String {
    Float(self).debugDescription
  }
}

extension BFloat: TextOutputStreamable {
  public func write<Target>(to target: inout Target) where Target: TextOutputStream {
    Float(self).write(to: &target)
  }
}

extension BFloat: AdditiveArithmetic {
    public static func + (lhs: BFloat, rhs: BFloat) -> BFloat {
        BFloat(Float(lhs) + Float(rhs))
    }
    
    
    public static func - (lhs: BFloat, rhs: BFloat) -> BFloat {
        BFloat(Float(lhs) - Float(rhs))
    }
}
extension BFloat: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt16) {
        _value = value;
    }
}

extension BFloat: ExpressibleByFloatLiteral {
    public typealias FloatLiteralType = Float
    
    @_transparent
    public init(floatLiteral value: Float) {
        let x = value.bitPattern;
        if _fastPath(x & 0x7FFF_FFFF < 0x7F80_0000) {
            let round_bit = UInt32(0x0000_8000);
            if (x & round_bit) != 0 && (x & (3 * round_bit - 1)) != 0 {
                _value = UInt16(x >> 16) + 1
            } else {
                _value = UInt16(x >> 16)
            }
        } else {
            _value = UInt16((x >> 16) | 0x0040);
        }
    }
}

extension BFloat: Numeric {
    public init?<T>(exactly source: T) where T : BinaryInteger {
        self = BFloat(Float(source))
    }
    
    public var magnitude: BFloat {
        BFloat(sign: .plus, exponent: self.exponent, significand: self.significand)
    }
    
    public static func * (lhs: BFloat, rhs: BFloat) -> BFloat {
        BFloat(Float(lhs) * Float(rhs))
    }
    
    public static func *= (lhs: inout BFloat, rhs: BFloat) {
        lhs = BFloat(Float(lhs) * Float(rhs))
    }
}

extension BFloat: BinaryFloatingPoint {
    public typealias Magnitude = BFloat
    public typealias Exponent = Int
    public typealias RawSignificand = UInt16
    
    
    @inlinable public static var exponentBitCount: Int {
      get {
        return 8
      }
    }
    @inlinable public static var significandBitCount: Int {
        get {
            return 8
        }
    }
    @inlinable internal static var _infinityExponent: UInt {
        @inline(__always) get { return 1 &<< (UInt(exponentBitCount) - 1) }
    }
    
    @inlinable internal static var _exponentBias: UInt {
        @inline(__always) get { return _infinityExponent &>> 1 }
    }
    
    @inlinable internal static var _significandMask: UInt16 {
        @inline(__always) get {
            return 1 &<< UInt16(significandBitCount) - 1
        }
    }
    
    @inlinable internal static var _quietNaNMask: UInt16 {
        @inline(__always) get {
            return 1 &<< UInt16(significandBitCount - 1)
        }
    }
    
    @inlinable public var bitPattern: UInt16 {
        get { return _value }
    }
    
    @inlinable public init(bitPattern: UInt16) {
        self.init(bitPattern)
    }
    
    public var sign: FloatingPointSign {
        get {
            let shift = BFloat.significandBitCount + BFloat.exponentBitCount
            return FloatingPointSign(rawValue: Int(bitPattern &>> UInt16(shift)))!
        }
    }
    @inlinable public var exponentBitPattern: UInt {
        get {
            return UInt(bitPattern &>> UInt16(BFloat.significandBitCount)) & BFloat._infinityExponent
        }
    }
    @inlinable public var significandBitPattern: UInt16 {
        get {
            return UInt16(bitPattern) & BFloat._significandMask
        }
    }
    
    public init(sign: FloatingPointSign, exponentBitPattern: UInt, significandBitPattern: UInt16) {
        let signShift = BFloat.significandBitCount + BFloat.exponentBitCount
        let sign = UInt16(sign == .minus ? 1 : 0)
        let exponent = UInt16(
            exponentBitPattern & BFloat._infinityExponent
        )
        let significand = UInt16(
            significandBitPattern & BFloat._significandMask
        )
        self.init(bitPattern:
                    sign &<< UInt16(signShift) |
                  exponent &<< UInt16(BFloat.significandBitCount) |
                  significand
        )
    }
    
    @inlinable public var isCanonical: Swift.Bool {
        get {
            // All Float and Double encodings are canonical in IEEE 754.
            //
            // On platforms that do not support subnormals, we treat them as
            // non-canonical encodings of zero.
            if Self.leastNonzeroMagnitude == Self.leastNormalMagnitude {
                if exponentBitPattern == 0 && significandBitPattern != 0 {
                    return false
                }
            }
            return true
        }
    }
    
    @inlinable public var binade: BFloat {
        get {
            guard _fastPath(isFinite) else { return .nan }
            if _slowPath(isSubnormal) {
                let bitPattern_ = (self * 0x1p10).bitPattern & (-BFloat.infinity).bitPattern
                return BFloat(bitPattern: bitPattern_) * 0x1p-10
            }
            return BFloat(bitPattern: bitPattern & (-BFloat.infinity).bitPattern)
        }
    }
    
    
    @inlinable public static var nan: BFloat {
        BFloat(0xFFC1)
    }
    
    @inlinable public static var signalingNaN: BFloat {
        BFloat(0xFF81)
    }
    
    @inlinable public static var infinity: BFloat {
        BFloat(0x7F80)
    }
    
    @inlinable public static var greatestFiniteMagnitude: BFloat {
        BFloat(0x7F7F)
    }
    
    @inlinable public static var pi: BFloat {
        BFloat(0x4049)
    }
    
    @inlinable public var ulp: BFloat {
      get {
        guard _fastPath(isFinite) else { return .nan }
        if _fastPath(isNormal) {
          let bitPattern_ = bitPattern & BFloat.infinity.bitPattern
          return BFloat(bitPattern: bitPattern_) * BFloat.ulpOfOne
        }
        // On arm, flush subnormal values to 0.
        return .leastNormalMagnitude * BFloat.ulpOfOne
      }
    }
    
    @inlinable public static var leastNormalMagnitude: BFloat {
        0x1.0p-14
    }
    
    @inlinable public static var leastNonzeroMagnitude: BFloat {
        return leastNormalMagnitude * ulpOfOne
    }
    
    @inlinable public static var ulpOfOne: BFloat {
        get {
            return 0x1.0p-8
        }
    }
    
    @inlinable public var exponent: Int {
        get {
            if !isFinite { return .max }
            if isZero { return .min }
            let provisional = Int(exponentBitPattern) - Int(BFloat._exponentBias)
            if isNormal { return provisional }
            let shift =
            BFloat.significandBitCount - significandBitPattern._binaryLogarithm()
            return provisional + 1 - shift
        }
    }
    
    public var significand: BFloat {
        get {
            if isNaN { return self }
            if isNormal {
                return BFloat(sign: .plus,
                              exponentBitPattern: BFloat._exponentBias,
                              significandBitPattern: significandBitPattern)
            }
            if isSubnormal {
                let shift =
                BFloat.significandBitCount - significandBitPattern._binaryLogarithm()
                return BFloat(
                    sign: .plus,
                    exponentBitPattern: BFloat._exponentBias,
                    significandBitPattern: significandBitPattern &<< shift
                )
            }
            // zero or infinity.
            return BFloat(
                sign: .plus,
                exponentBitPattern: exponentBitPattern,
                significandBitPattern: 0
            )
        }
    }
    
    @inlinable public init(sign: FloatingPointSign, exponent: Int, significand: BFloat) {
        var result = significand
        if sign == .minus { result = -result }
        if significand.isFinite && !significand.isZero {
            var clamped = exponent
            let leastNormalExponent = 1 - Int(BFloat._exponentBias)
            let greatestFiniteExponent = Int(BFloat._exponentBias)
            if clamped < leastNormalExponent {
                clamped = max(clamped, 3*leastNormalExponent)
                while clamped < leastNormalExponent {
                    result  *= BFloat.leastNormalMagnitude
                    clamped -= leastNormalExponent
                }
            }
            else if clamped > greatestFiniteExponent {
                clamped = min(clamped, 3*greatestFiniteExponent)
                let step = BFloat(sign: .plus,
                                  exponentBitPattern: BFloat._infinityExponent - 1,
                                  significandBitPattern: 0)
                while clamped > greatestFiniteExponent {
                    result  *= step
                    clamped -= greatestFiniteExponent
                }
            }
            let scale = BFloat(
                sign: .plus,
                exponentBitPattern: UInt(Int(BFloat._exponentBias) + clamped),
                significandBitPattern: 0
            )
            result = result * scale
        }
        self = result
    }
    
    @inlinable public var significandWidth: Int {
        get {
            let trailingZeroBits = significandBitPattern.trailingZeroBitCount
            if isNormal {
                guard significandBitPattern != 0 else { return 0 }
                return BFloat.significandBitCount &- trailingZeroBits
            }
            if isSubnormal {
                let leadingZeroBits = significandBitPattern.leadingZeroBitCount
                return UInt16.bitWidth &- (trailingZeroBits &+ leadingZeroBits &+ 1)
            }
            return -1
        }
    }
    
    @inlinable public var nextUp: BFloat {
        get {
            // Silence signaling NaNs, map -0 to +0.
            let x = self + 0
            if _fastPath(x < .infinity) {
                let increment = Int16(bitPattern: x.bitPattern) &>> 15 | 1
                let bitPattern_ = x.bitPattern &+ UInt16(bitPattern: increment)
                return BFloat(bitPattern: bitPattern_)
            }
            return x
        }
    }
    
    public mutating func round(_ rule: FloatingPointRoundingRule) {
        var f = Float(self)
        f.round(rule)
        self = BFloat(f)
    }
    
    public static func /= (lhs: inout BFloat, rhs: BFloat) {
        lhs = BFloat(Float(lhs) / Float(rhs))
    }
    
    public static func / (lhs: BFloat, rhs: BFloat) -> BFloat {
        BFloat(Float(lhs) / Float(rhs))
    }
    
    @inlinable @inline(__always) public mutating func formRemainder(dividingBy other: BFloat) {
        self = BFloat(_stdlib_remainderf(Float(self), Float(other)))
    }
    
    @inlinable @inline(__always) public mutating func formTruncatingRemainder(dividingBy other: BFloat) {
        var f = Float(self)
        f.formTruncatingRemainder(dividingBy: Float(other))
        self = BFloat(f)
    }
    
    @_transparent public mutating func formSquareRoot() {
        self = BFloat(_stdlib_squareRootf(Float(self)))
    }
    
    public mutating func addProduct(_ lhs: BFloat, _ rhs: BFloat) {
        var f = Float(self)
        f.addProduct(Float(lhs), Float(rhs))
        self = BFloat(f)
    }
    
    public func isEqual(to other: BFloat) -> Bool {
        self._value == other._value
    }
    
    public func isLess(than other: BFloat) -> Bool {
        self._value < other._value
    }
    
    public func isLessThanOrEqualTo(_ other: BFloat) -> Bool {
        self._value <= other._value
    }
    
    public var isNormal: Bool {
        false
    }
    
    @inlinable public var isFinite: Bool {
      @inline(__always) get {
        return exponentBitPattern < BFloat._infinityExponent
      }
    }
    
    @inlinable public var isZero: Bool {
      @inline(__always) get {
        return exponentBitPattern == 0 && significandBitPattern == 0
      }
    }
    @inlinable public var isSubnormal: Bool {
      @inline(__always) get {
        return exponentBitPattern == 0 && significandBitPattern != 0
      }
    }
    @inlinable public var isInfinite: Bool {
      @inline(__always) get {
        return !isFinite && significandBitPattern == 0
      }
    }
    @inlinable public var isNaN: Bool {
      @inline(__always) get {
          return _value == BFloat.nan._value
      }
    }
    @inlinable public var isSignalingNaN: Bool {
      @inline(__always) get {
          return _value == BFloat.signalingNaN._value
      }
    }
}

extension BFloat: Strideable {
    public typealias Stride = BFloat
    
    @_transparent
    public func distance(to other: Self) -> Self.Stride {
        return other - self
    }
    
    @_transparent
    public func advanced(by n: Self.Stride) -> Self {
        self + n
    }
}

extension BFloat: Hashable {
    @inlinable public func hash(into hasher: inout Hasher) {
        // To satisfy the axiom that equality implies hash equality, we need to
        // finesse the hash value of -0.0 to match +0.0.
        let v = isZero ? 0 : self
        hasher.combine(v.bitPattern)
    }
}

extension BFloat: Codable {
    
    /**
     Creates a new instance by decoding from the given decoder.

     The way in which `BFloat` decodes itself is by first decoding the next largest
     floating-point type that conforms to `Decodable` and then attempting to cast it
     down to `BFloat`. This initializer throws an error if reading from the decoder
     fails, if the data read is corrupted or otherwise invalid, or if the decoded
     floating-point value is too large to fit in a `BFloat` type.

     - Parameters:
       - decoder: The decoder to read data from.
     */
    @_transparent
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let float = try container.decode(Float.self)

        guard float.isInfinite || float.isNaN || abs(float) <= Float(BFloat.greatestFiniteMagnitude) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath, debugDescription: "Parsed number \(float) does not fit in \(type(of: self))."))
        }

        self.init(float)
    }

    /**
     Encodes this value into the given encoder.

     The way in which `BFloat` encodes itself is by first prompting itself to the next
     largest floating-point type that conforms to `Encodable` and encoding that value
     to the encoder. This function throws an error if any values are invalid for the
     given encoder’s format.

     - Parameters:
       - encoder: The encoder to write data to.

     - Note: This documentation comment was copied from `Double`.
     */
    @_transparent
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Float(self))
    }
}


extension BFloat : SIMDScalar {

    public typealias SIMDMaskScalar = Int16

    /// Storage for a vector of two brain floating-point values.
    @frozen @_alignment(4) public struct SIMD2Storage : SIMDStorage, Sendable {
        public var _value: UInt16.SIMD2Storage

        /// The number of scalars, or elements, in the vector.
        @_transparent public var scalarCount: Swift.Int {
            @_transparent get {
                return _value.scalarCount
            }
        }

        /// Creates a vector with zero in all lanes.
        @_transparent public init() {
            _value = UInt16.SIMD2Storage.init();
        }
        @_alwaysEmitIntoClient internal init(_ _builtin: UInt16.SIMD2Storage) {
            _value = _builtin
        }
        
        /// Accesses the element at the specified index.
        ///
        /// - Parameter index: The index of the element to access. `index` must be in
        ///   the range `0..<scalarCount`.
        public subscript(index: Int) -> BFloat {
          @_transparent get {
              BFloat(_value[index])
          }
          @_transparent set {
              _value[index] = newValue._value
          }
        }
        /// The type of scalars in the vector space.
        public typealias Scalar = BFloat
    }
    
    /// Storage for a vector of four brain floating-point values.
    @frozen @_alignment(8) public struct SIMD4Storage : SIMDStorage, Sendable {
        public var _value: UInt16.SIMD4Storage

        /// The number of scalars, or elements, in the vector.
        @_transparent public var scalarCount: Swift.Int {
            @_transparent get {
                return _value.scalarCount
            }
        }

        /// Creates a vector with zero in all lanes.
        @_transparent public init() {
            _value = UInt16.SIMD4Storage.init();
        }
        @_alwaysEmitIntoClient internal init(_ _builtin: UInt16.SIMD4Storage) {
            _value = _builtin
        }
        
        /// Accesses the element at the specified index.
        ///
        /// - Parameter index: The index of the element to access. `index` must be in
        ///   the range `0..<scalarCount`.
        public subscript(index: Int) -> BFloat {
          @_transparent get {
              BFloat(_value[index])
          }
          @_transparent set {
              _value[index] = newValue._value
          }
        }
        /// The type of scalars in the vector space.
        public typealias Scalar = BFloat
    }
    
    /// Storage for a vector of four brain floating-point values.
    @frozen @_alignment(16) public struct SIMD8Storage : SIMDStorage, Sendable {
        public var _value: UInt16.SIMD8Storage

        /// The number of scalars, or elements, in the vector.
        @_transparent public var scalarCount: Swift.Int {
            @_transparent get {
                return _value.scalarCount
            }
        }

        /// Creates a vector with zero in all lanes.
        @_transparent public init() {
            _value = UInt16.SIMD8Storage.init();
        }
        @_alwaysEmitIntoClient internal init(_ _builtin: UInt16.SIMD8Storage) {
            _value = _builtin
        }
        
        /// Accesses the element at the specified index.
        ///
        /// - Parameter index: The index of the element to access. `index` must be in
        ///   the range `0..<scalarCount`.
        public subscript(index: Int) -> BFloat {
          @_transparent get {
              BFloat(_value[index])
          }
          @_transparent set {
              _value[index] = newValue._value
          }
        }
        /// The type of scalars in the vector space.
        public typealias Scalar = BFloat
    }
    
    /// Storage for a vector of four brain floating-point values.
    @frozen @_alignment(16) public struct SIMD16Storage : SIMDStorage, Sendable {
        public var _value: UInt16.SIMD16Storage

        /// The number of scalars, or elements, in the vector.
        @_transparent public var scalarCount: Swift.Int {
            @_transparent get {
                return _value.scalarCount
            }
        }

        /// Creates a vector with zero in all lanes.
        @_transparent public init() {
            _value = UInt16.SIMD16Storage.init();
        }
        @_alwaysEmitIntoClient internal init(_ _builtin: UInt16.SIMD16Storage) {
            _value = _builtin
        }
        
        /// Accesses the element at the specified index.
        ///
        /// - Parameter index: The index of the element to access. `index` must be in
        ///   the range `0..<scalarCount`.
        public subscript(index: Int) -> BFloat {
          @_transparent get {
              BFloat(_value[index])
          }
          @_transparent set {
              _value[index] = newValue._value
          }
        }
        /// The type of scalars in the vector space.
        public typealias Scalar = BFloat
    }
    
    /// Storage for a vector of four brain floating-point values.
    @frozen @_alignment(16) public struct SIMD32Storage : SIMDStorage, Sendable {
        public var _value: UInt16.SIMD32Storage

        /// The number of scalars, or elements, in the vector.
        @_transparent public var scalarCount: Swift.Int {
            @_transparent get {
                return _value.scalarCount
            }
        }

        /// Creates a vector with zero in all lanes.
        @_transparent public init() {
            _value = UInt16.SIMD32Storage.init();
        }
        @_alwaysEmitIntoClient internal init(_ _builtin: UInt16.SIMD32Storage) {
            _value = _builtin
        }
        
        /// Accesses the element at the specified index.
        ///
        /// - Parameter index: The index of the element to access. `index` must be in
        ///   the range `0..<scalarCount`.
        public subscript(index: Int) -> BFloat {
          @_transparent get {
              BFloat(_value[index])
          }
          @_transparent set {
              _value[index] = newValue._value
          }
        }
        /// The type of scalars in the vector space.
        public typealias Scalar = BFloat
    }
    
    /// Storage for a vector of four brain floating-point values.
    @frozen @_alignment(16) public struct SIMD64Storage : SIMDStorage, Sendable {
        public var _value: UInt16.SIMD64Storage

        /// The number of scalars, or elements, in the vector.
        @_transparent public var scalarCount: Swift.Int {
            @_transparent get {
                return _value.scalarCount
            }
        }

        /// Creates a vector with zero in all lanes.
        @_transparent public init() {
            _value = UInt16.SIMD64Storage.init();
        }
        @_alwaysEmitIntoClient internal init(_ _builtin: UInt16.SIMD64Storage) {
            _value = _builtin
        }
        
        /// Accesses the element at the specified index.
        ///
        /// - Parameter index: The index of the element to access. `index` must be in
        ///   the range `0..<scalarCount`.
        public subscript(index: Int) -> BFloat {
          @_transparent get {
              BFloat(_value[index])
          }
          @_transparent set {
              _value[index] = newValue._value
          }
        }
        /// The type of scalars in the vector space.
        public typealias Scalar = BFloat
    }
}
