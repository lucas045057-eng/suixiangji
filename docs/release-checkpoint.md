# WealthMate / 随想记 Release Checkpoint

## Frozen source

```text
Flutter verified SHA：c5e3603baffdaf31c83b9fa876b7be0fd10873e1
Backend SHA：e5529e33187adab41444a089a3c98aefab3ef4ab
Tag：sync-v1.0-rc1
Tag target：c5e3603baffdaf31c83b9fa876b7be0fd10873e1
Branch：sync-recovery（待合并至正式默认分支）
```

## Verified artifacts

```text
Android APK SHA256：
006FFF44893B2B2E2F1237FB1D85913A442E11D3E922A32A16537BD7A05C990D

Windows EXE SHA256：
E9A7FA1FC3E8E4D05781CBA095710567FD1782F3D339392C325260D1911D6EFC

Windows data/app.so SHA256：
D4759BDB4D80F1C41A0AF12CBC78FE3AD7EAEC34FCDF1BFA7E3CABEE1397EF6F
```

构建二进制不提交到 Git；部署时以 SHA256 校验实际安装包。

## Verification

```text
Flutter 134/134 PASS
flutter analyze PASS
Backend 46/46 PASS
compileall PASS
Phase 7A PASS
Phase 7B PASS
Final Regression PASS
```

Backend 健康接口应返回：

```json
{
  "status": "ok",
  "service": "suixiangji-v1",
  "git_sha": "e5529e33187adab41444a089a3c98aefab3ef4ab"
}
```

## Release statement

```text
CORE LOCAL-FIRST MULTI-DEVICE SYNC VERIFICATION COMPLETE
```

This checkpoint proves the tested sync matrix. It does not mean the software can never contain another synchronization bug.
