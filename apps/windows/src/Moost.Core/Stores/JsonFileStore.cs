using System.Text.Json;
using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// 人が読める JSON ファイルの読み書き基盤（conformance A1〜A3）。
/// リファレンス実装: <c>packages/core/lib/src/store/json_file_store.dart</c>。
///
/// <list type="bullet">
/// <item>A1 書き込みは一時ファイル → リネーム（書き込み中のクラッシュで本体を壊さない）</item>
/// <item>A2 JSON として読めない既存ファイルは上書きせず <c>&lt;name&gt;.corrupt-&lt;timestamp&gt;</c> へ退避し、空として扱う</item>
/// <item>A3 読み取りエラー（権限等）は握りつぶさず例外で伝播する（null 扱いにして既存データを失わない）</item>
/// </list>
/// </summary>
public sealed class JsonFileStore
{
    /// <summary>一時ファイルの接尾辞（A1）。</summary>
    public const string TempSuffix = ".tmp";

    private static readonly JsonSerializerOptions IndentedOptions = new()
    {
        WriteIndented = true,
        // 日本語や危険文字（` $ ; | など）を \uXXXX に潰さず、人が読める形で保存する
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    /// <summary>読み書き対象の絶対パス。</summary>
    public string FilePath { get; }

    public JsonFileStore(string filePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        FilePath = filePath;
    }

    /// <summary>
    /// JSON オブジェクトとして読み込む。存在しなければ null（A3: 存在しないだけは正常）。
    /// 壊れていた場合は退避して null（A2）。
    /// </summary>
    /// <exception cref="IOException">読み取り自体に失敗した場合（権限エラー等）。A3 により伝播させる。</exception>
    /// <exception cref="UnauthorizedAccessException">読み取り権限がない場合。A3 により伝播させる。</exception>
    public JsonObject? Read()
    {
        // 存在しないだけなら空ストア扱い（呼び出し側はデフォルトを返す）
        if (!File.Exists(FilePath))
        {
            return null;
        }

        // 権限エラー等はここで握りつぶさない。null を返すと「空のストア」とみなして
        // 上書き保存し、既存データを失う（A3）。
        var text = File.ReadAllText(FilePath);

        JsonNode? parsed = null;
        try
        {
            parsed = JsonNode.Parse(text);
        }
        catch (JsonException)
        {
            // 壊れた JSON は退避して空扱い（A2）
            Quarantine();
            return null;
        }

        if (parsed is not JsonObject jsonObject)
        {
            // オブジェクトでない（配列・スカラー・空）も契約違反なので退避する（A2）
            Quarantine();
            return null;
        }

        return jsonObject;
    }

    /// <summary>
    /// アトミックに書き込む（A1）: 同ディレクトリの一時ファイルへ書き → リネームで差し替える。
    /// </summary>
    public void Write(JsonObject json)
    {
        var directory = Path.GetDirectoryName(FilePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var tempPath = FilePath + TempSuffix;
        var text = json.ToJsonString(IndentedOptions) + "\n";

        using (var stream = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None))
        using (var writer = new StreamWriter(stream, new System.Text.UTF8Encoding(false)))
        {
            writer.Write(text);
            writer.Flush();
            stream.Flush(flushToDisk: true);
        }

        // 同一ボリューム内の置換は原子的（途中で落ちても本体は前の内容のまま）
        File.Move(tempPath, FilePath, overwrite: true);
    }

    /// <summary>
    /// 壊れたファイルを <c>&lt;name&gt;.corrupt-&lt;timestamp&gt;</c> へ退避する（A2）。
    /// 上書きも削除もしない（データを黙って失わない）。
    /// </summary>
    private void Quarantine()
    {
        // リファレンス実装と同じ形式: UTC ISO8601 の ':' を '-' に置換する
        var stamp = DateTime.UtcNow
            .ToString(IsoUtc.FormatString, System.Globalization.CultureInfo.InvariantCulture)
            .Replace(":", "-", StringComparison.Ordinal);
        File.Move(FilePath, FilePath + ".corrupt-" + stamp, overwrite: true);
    }
}
