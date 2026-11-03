import 'package:flutter_test/flutter_test.dart';
import 'package:xmlyfm/services/sign.dart';

// baseInfo v4 sign 向量测试。
// 期望值由 openssl 独立生成交叉验证：
//   明文 trackId + "android" + last4 + "0zpnlXAG" 经 PKCS7 填充后
//   openssl enc -aes-128-cbc -K 9e3B103bA2d2cb56e805B3cCeB2512E3
//     -iv hex("M%6)W5F6@Jj~" + last4)，输出 Base64URL。
void main() {
  group('baseInfoSign', () {
    test('向量 1: trackId=12345678, ts=1700000000123', () {
      final sign = baseInfoSign(trackId: 12345678, timestampMs: 1700000000123);
      expect(sign, 'ERrSMDE3a86v5vXKFv3eDOvojJSFWSvJneEthoNb5BU=');
    });

    test('向量 2: trackId=409801642, ts=1793689082044', () {
      final sign = baseInfoSign(trackId: 409801642, timestampMs: 1793689082044);
      expect(sign, 'UF8ajs5_fF8KU36mkxtiSJNi8XlDi4F9UGbGmwHWFao=');
    });

    test('输出是 Base64URL 形态（无 + / 字符）', () {
      final sign = baseInfoSign(trackId: 409801642, timestampMs: 1793689082044);
      expect(sign.contains('+'), isFalse);
      expect(sign.contains('/'), isFalse);
    });

    test('不同 salt 产生不同签名', () {
      final a = baseInfoSign(trackId: 1, timestampMs: 1700000000123);
      final b = baseInfoSign(
          trackId: 1, timestampMs: 1700000000123, salt: 'dnrXjC2V');
      expect(a, isNot(b));
    });
  });

  group('hexDecode', () {
    test('签名 key 解出 16 字节', () {
      final bytes = hexDecode('9e3B103bA2d2cb56e805B3cCeB2512E3');
      expect(bytes.length, 16);
      expect(bytes.first, 0x9e);
      expect(bytes.last, 0xe3);
    });
  });
}
