import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

/// baseInfo v4 的 sign 算法（XIMALAYA_API.md §5.2，逆自官方
/// host/manager/request/c.java，已被服务端接受验证）：
///   last4 = str(currentTimeMillis) 末 4 位
///   iv    = "M%6)W5F6@Jj~" + last4（16B）
///   key   = hexDecode("9e3B103bA2d2cb56e805B3cCeB2512E3")（AES-128）
///   plain = trackId + "android" + last4 + salt
///   sign  = Base64URL(AES-128-CBC/PKCS5 加密 plain)
/// salt：普通详情 "0zpnlXAG"；视频 "dnrXjC2V"；缺省 "IZPdBDZ5"。
String baseInfoSign({
  required int trackId,
  required int timestampMs,
  String salt = '0zpnlXAG',
}) {
  final tsStr = timestampMs.toString();
  final last4 = tsStr.substring(tsStr.length - 4);
  final key = Key(Uint8List.fromList(hexDecode(_signKeyHex)));
  final iv = IV.fromUtf8('M%6)W5F6@Jj~$last4');
  final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
  final encrypted = encrypter.encrypt('${trackId}android$last4$salt', iv: iv);
  return base64Url.encode(encrypted.bytes);
}

const String _signKeyHex = '9e3B103bA2d2cb56e805B3cCeB2512E3';

/// hex 字符串 -> 字节
List<int> hexDecode(String hex) {
  final out = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}
