# わんぱくヌガヌガー in ISUCON 6Q

## メンバー

- @ik11235
- @harukasan
- @moyashipan

## 結果

ベストスコアは34,000点ぐらいでおそらく予選敗退

## 方針

1. htmlifyの結果をcontentのハッシュをキーとしてmemcachedにキャッシュする
2. キーワードのTRIE木を作っておいてhtmlifyする (https://github.com/harukasan/wanpaku20150918/pull/16)
3. TRIE木が間に合わなかったときのためにcontentのunigramをつくっておく（後に2-gramで実装）←ココマデ

