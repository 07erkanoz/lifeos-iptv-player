import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ku.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ku'),
    Locale('ru'),
    Locale('tr'),
  ];

  /// No description provided for @appName.
  ///
  /// In tr, this message translates to:
  /// **'LifeOs TV'**
  String get appName;

  /// No description provided for @welcomeMessage.
  ///
  /// In tr, this message translates to:
  /// **'Hoş Geldiniz'**
  String get welcomeMessage;

  /// No description provided for @loginWithXtream.
  ///
  /// In tr, this message translates to:
  /// **'Xtream Codes ile Giriş Yap'**
  String get loginWithXtream;

  /// No description provided for @loadM3U.
  ///
  /// In tr, this message translates to:
  /// **'M3U Playlist Yükle'**
  String get loadM3U;

  /// No description provided for @restoreBackup.
  ///
  /// In tr, this message translates to:
  /// **'Yedekten Geri Yükle'**
  String get restoreBackup;

  /// No description provided for @username.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı Adı'**
  String get username;

  /// No description provided for @password.
  ///
  /// In tr, this message translates to:
  /// **'Şifre'**
  String get password;

  /// No description provided for @url.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu URL'**
  String get url;

  /// No description provided for @login.
  ///
  /// In tr, this message translates to:
  /// **'Giriş Yap'**
  String get login;

  /// No description provided for @settings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get settings;

  /// No description provided for @dashboard.
  ///
  /// In tr, this message translates to:
  /// **'Ana Sayfa'**
  String get dashboard;

  /// No description provided for @liveTV.
  ///
  /// In tr, this message translates to:
  /// **'Canlı TV'**
  String get liveTV;

  /// No description provided for @movies.
  ///
  /// In tr, this message translates to:
  /// **'Filmler'**
  String get movies;

  /// No description provided for @series.
  ///
  /// In tr, this message translates to:
  /// **'Diziler'**
  String get series;

  /// No description provided for @favorites.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler'**
  String get favorites;

  /// No description provided for @search.
  ///
  /// In tr, this message translates to:
  /// **'Ara'**
  String get search;

  /// No description provided for @accounts.
  ///
  /// In tr, this message translates to:
  /// **'Hesaplar'**
  String get accounts;

  /// No description provided for @appearance.
  ///
  /// In tr, this message translates to:
  /// **'Görünüm'**
  String get appearance;

  /// No description provided for @player.
  ///
  /// In tr, this message translates to:
  /// **'Oynatıcı'**
  String get player;

  /// No description provided for @language.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get language;

  /// No description provided for @dataBackup.
  ///
  /// In tr, this message translates to:
  /// **'Veri ve Yedekleme'**
  String get dataBackup;

  /// No description provided for @about.
  ///
  /// In tr, this message translates to:
  /// **'Hakkında'**
  String get about;

  /// No description provided for @darkMode.
  ///
  /// In tr, this message translates to:
  /// **'Karanlık Mod'**
  String get darkMode;

  /// No description provided for @darkModeDesc.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama için karanlık tema kullan'**
  String get darkModeDesc;

  /// No description provided for @hardwareAcceleration.
  ///
  /// In tr, this message translates to:
  /// **'Donanım Hızlandırma'**
  String get hardwareAcceleration;

  /// No description provided for @hardwareAccelerationDesc.
  ///
  /// In tr, this message translates to:
  /// **'Video çözme için GPU kullan (Önerilen)'**
  String get hardwareAccelerationDesc;

  /// No description provided for @bufferDuration.
  ///
  /// In tr, this message translates to:
  /// **'Tampon Süresi'**
  String get bufferDuration;

  /// No description provided for @clearCache.
  ///
  /// In tr, this message translates to:
  /// **'Önbelleği Temizle'**
  String get clearCache;

  /// No description provided for @clearCacheDesc.
  ///
  /// In tr, this message translates to:
  /// **'Resimleri ve geçici dosyaları temizle'**
  String get clearCacheDesc;

  /// No description provided for @refreshData.
  ///
  /// In tr, this message translates to:
  /// **'Verileri Yenile'**
  String get refreshData;

  /// No description provided for @refreshDataDesc.
  ///
  /// In tr, this message translates to:
  /// **'Tüm kanalları ve kategorileri yeniden senkronize et'**
  String get refreshDataDesc;

  /// No description provided for @noAccountWarning.
  ///
  /// In tr, this message translates to:
  /// **'Hesap yapılandırılmamış. İzlemeye başlamak için Xtream veya M3U hesabı ekleyin.'**
  String get noAccountWarning;

  /// No description provided for @goToSettings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlara Git'**
  String get goToSettings;

  /// No description provided for @savedAccounts.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı Hesaplar'**
  String get savedAccounts;

  /// No description provided for @noAccountsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz hesap eklenmedi.'**
  String get noAccountsYet;

  /// No description provided for @setDefault.
  ///
  /// In tr, this message translates to:
  /// **'Varsayılan Yap'**
  String get setDefault;

  /// No description provided for @defaultLabel.
  ///
  /// In tr, this message translates to:
  /// **'Varsayılan'**
  String get defaultLabel;

  /// No description provided for @categories.
  ///
  /// In tr, this message translates to:
  /// **'Kategoriler'**
  String get categories;

  /// No description provided for @selectCategory.
  ///
  /// In tr, this message translates to:
  /// **'Bir Kategori Seçin'**
  String get selectCategory;

  /// No description provided for @selectChannel.
  ///
  /// In tr, this message translates to:
  /// **'Bir Kanal Seçin'**
  String get selectChannel;

  /// No description provided for @syncing.
  ///
  /// In tr, this message translates to:
  /// **'Senkronize ediliyor...'**
  String get syncing;

  /// No description provided for @syncContent.
  ///
  /// In tr, this message translates to:
  /// **'İçerik senkronize ediliyor...'**
  String get syncContent;

  /// No description provided for @syncTriggered.
  ///
  /// In tr, this message translates to:
  /// **'Senkronizasyon başladı...'**
  String get syncTriggered;

  /// No description provided for @cacheClearedMsg.
  ///
  /// In tr, this message translates to:
  /// **'Önbellek Temizlendi'**
  String get cacheClearedMsg;

  /// No description provided for @noActiveAccount.
  ///
  /// In tr, this message translates to:
  /// **'Aktif hesap bulunamadı'**
  String get noActiveAccount;

  /// No description provided for @play.
  ///
  /// In tr, this message translates to:
  /// **'Oynat'**
  String get play;

  /// No description provided for @resume.
  ///
  /// In tr, this message translates to:
  /// **'Devam Et'**
  String get resume;

  /// No description provided for @details.
  ///
  /// In tr, this message translates to:
  /// **'Detaylar'**
  String get details;

  /// No description provided for @trailer.
  ///
  /// In tr, this message translates to:
  /// **'Fragman'**
  String get trailer;

  /// No description provided for @moreInfo.
  ///
  /// In tr, this message translates to:
  /// **'Daha Fazla Bilgi'**
  String get moreInfo;

  /// No description provided for @recentlyAdded.
  ///
  /// In tr, this message translates to:
  /// **'Son Eklenenler'**
  String get recentlyAdded;

  /// No description provided for @version.
  ///
  /// In tr, this message translates to:
  /// **'Sürüm'**
  String get version;

  /// No description provided for @premiumExperience.
  ///
  /// In tr, this message translates to:
  /// **'Premium IPTV Deneyimi'**
  String get premiumExperience;

  /// No description provided for @xtreamCodes.
  ///
  /// In tr, this message translates to:
  /// **'Xtream Codes'**
  String get xtreamCodes;

  /// No description provided for @xtreamCodesDesc.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu URL + kimlik bilgileri'**
  String get xtreamCodesDesc;

  /// No description provided for @m3uPlaylist.
  ///
  /// In tr, this message translates to:
  /// **'M3U Playlist'**
  String get m3uPlaylist;

  /// No description provided for @m3uPlaylistDesc.
  ///
  /// In tr, this message translates to:
  /// **'URL veya yerel dosya'**
  String get m3uPlaylistDesc;

  /// No description provided for @systemDefault.
  ///
  /// In tr, this message translates to:
  /// **'Sistem Varsayılanı'**
  String get systemDefault;

  /// No description provided for @accountName.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Adı'**
  String get accountName;

  /// No description provided for @accountNameHint.
  ///
  /// In tr, this message translates to:
  /// **'ör. IPTV\'m'**
  String get accountNameHint;

  /// No description provided for @playlistName.
  ///
  /// In tr, this message translates to:
  /// **'Playlist Adı'**
  String get playlistName;

  /// No description provided for @playlistNameHint.
  ///
  /// In tr, this message translates to:
  /// **'ör. Listem'**
  String get playlistNameHint;

  /// No description provided for @loadPlaylist.
  ///
  /// In tr, this message translates to:
  /// **'Playlist Yükle'**
  String get loadPlaylist;

  /// No description provided for @selectM3UFile.
  ///
  /// In tr, this message translates to:
  /// **'M3U Dosyası Seç'**
  String get selectM3UFile;

  /// No description provided for @or.
  ///
  /// In tr, this message translates to:
  /// **'VEYA'**
  String get or;

  /// No description provided for @allMovies.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Filmler'**
  String get allMovies;

  /// No description provided for @searchMovies.
  ///
  /// In tr, this message translates to:
  /// **'Film ara...'**
  String get searchMovies;

  /// No description provided for @allSeries.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Diziler'**
  String get allSeries;

  /// No description provided for @searchSeries.
  ///
  /// In tr, this message translates to:
  /// **'Dizi ara...'**
  String get searchSeries;

  /// No description provided for @director.
  ///
  /// In tr, this message translates to:
  /// **'Yönetmen'**
  String get director;

  /// No description provided for @cast.
  ///
  /// In tr, this message translates to:
  /// **'Oyuncular'**
  String get cast;

  /// No description provided for @genre.
  ///
  /// In tr, this message translates to:
  /// **'Tür'**
  String get genre;

  /// No description provided for @year.
  ///
  /// In tr, this message translates to:
  /// **'Yıl'**
  String get year;

  /// No description provided for @rating.
  ///
  /// In tr, this message translates to:
  /// **'Puan'**
  String get rating;

  /// No description provided for @season.
  ///
  /// In tr, this message translates to:
  /// **'Sezon'**
  String get season;

  /// No description provided for @episode.
  ///
  /// In tr, this message translates to:
  /// **'Bölüm'**
  String get episode;

  /// No description provided for @episodes.
  ///
  /// In tr, this message translates to:
  /// **'Bölümler'**
  String get episodes;

  /// No description provided for @movie.
  ///
  /// In tr, this message translates to:
  /// **'FİLM'**
  String get movie;

  /// No description provided for @seriesLabel.
  ///
  /// In tr, this message translates to:
  /// **'DİZİ'**
  String get seriesLabel;

  /// No description provided for @live.
  ///
  /// In tr, this message translates to:
  /// **'CANLI'**
  String get live;

  /// No description provided for @programGuide.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Akışı'**
  String get programGuide;

  /// No description provided for @noProgramGuide.
  ///
  /// In tr, this message translates to:
  /// **'Yayın akışı bilgisi bulunamadı'**
  String get noProgramGuide;

  /// No description provided for @nowPlaying.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi'**
  String get nowPlaying;

  /// No description provided for @watch.
  ///
  /// In tr, this message translates to:
  /// **'İzle'**
  String get watch;

  /// No description provided for @addToFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilere Ekle'**
  String get addToFavorites;

  /// No description provided for @continueWatching.
  ///
  /// In tr, this message translates to:
  /// **'İzlemeye Devam Et'**
  String get continueWatching;

  /// No description provided for @continueWatchingMovies.
  ///
  /// In tr, this message translates to:
  /// **'İzlemeye Devam Et - Filmler'**
  String get continueWatchingMovies;

  /// No description provided for @continueWatchingSeries.
  ///
  /// In tr, this message translates to:
  /// **'İzlemeye Devam Et - Diziler'**
  String get continueWatchingSeries;

  /// No description provided for @noWatchedMovies.
  ///
  /// In tr, this message translates to:
  /// **'Henüz izlenen film yok'**
  String get noWatchedMovies;

  /// No description provided for @noWatchedSeries.
  ///
  /// In tr, this message translates to:
  /// **'Henüz izlenen dizi yok'**
  String get noWatchedSeries;

  /// No description provided for @favoritesHistory.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler & İzleme Geçmişi'**
  String get favoritesHistory;

  /// No description provided for @playerSettings.
  ///
  /// In tr, this message translates to:
  /// **'Oynatıcı Ayarları'**
  String get playerSettings;

  /// No description provided for @audioTrack.
  ///
  /// In tr, this message translates to:
  /// **'Ses İzi'**
  String get audioTrack;

  /// No description provided for @subtitle.
  ///
  /// In tr, this message translates to:
  /// **'Altyazı'**
  String get subtitle;

  /// No description provided for @playbackSpeed.
  ///
  /// In tr, this message translates to:
  /// **'Oynatma Hızı'**
  String get playbackSpeed;

  /// No description provided for @noOptions.
  ///
  /// In tr, this message translates to:
  /// **'Seçenek bulunamadı'**
  String get noOptions;

  /// No description provided for @resumePlayback.
  ///
  /// In tr, this message translates to:
  /// **'Kaldığınız yerden devam edilsin mi?'**
  String get resumePlayback;

  /// No description provided for @yes.
  ///
  /// In tr, this message translates to:
  /// **'Evet'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In tr, this message translates to:
  /// **'Hayır'**
  String get no;

  /// No description provided for @nextEpisode.
  ///
  /// In tr, this message translates to:
  /// **'SIRADAKİ BÖLÜM'**
  String get nextEpisode;

  /// No description provided for @playNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi Oynat'**
  String get playNow;

  /// No description provided for @cancel.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get cancel;

  /// No description provided for @clearAll.
  ///
  /// In tr, this message translates to:
  /// **'Temizle'**
  String get clearAll;

  /// No description provided for @selectAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Seçin'**
  String get selectAccount;

  /// No description provided for @noAccountFound.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Bulunamadı'**
  String get noAccountFound;

  /// No description provided for @recentlyAddedMovies.
  ///
  /// In tr, this message translates to:
  /// **'Son Eklenen Filmler'**
  String get recentlyAddedMovies;

  /// No description provided for @recentlyAddedSeries.
  ///
  /// In tr, this message translates to:
  /// **'Son Eklenen Diziler'**
  String get recentlyAddedSeries;

  /// No description provided for @accountManagement.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Yönetimi'**
  String get accountManagement;

  /// No description provided for @manageAccounts.
  ///
  /// In tr, this message translates to:
  /// **'IPTV hesaplarınızı yönetin'**
  String get manageAccounts;

  /// No description provided for @addXtreamAccount.
  ///
  /// In tr, this message translates to:
  /// **'Xtream Hesabı Ekle'**
  String get addXtreamAccount;

  /// No description provided for @addM3UPlaylist.
  ///
  /// In tr, this message translates to:
  /// **'M3U Playlist Ekle'**
  String get addM3UPlaylist;

  /// No description provided for @editAccount.
  ///
  /// In tr, this message translates to:
  /// **'Düzenle: {name}'**
  String editAccount(String name);

  /// No description provided for @deleteAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabı Sil'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" hesabını silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'**
  String deleteAccountConfirm(String name);

  /// No description provided for @accountNameUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Hesap adı güncellendi'**
  String get accountNameUpdated;

  /// No description provided for @languageSet.
  ///
  /// In tr, this message translates to:
  /// **'Dil {lang} olarak ayarlandı'**
  String languageSet(String lang);

  /// No description provided for @selectLanguage.
  ///
  /// In tr, this message translates to:
  /// **'Tercih ettiğiniz dili seçin'**
  String get selectLanguage;

  /// No description provided for @visible.
  ///
  /// In tr, this message translates to:
  /// **'görünür'**
  String get visible;

  /// No description provided for @hidden.
  ///
  /// In tr, this message translates to:
  /// **'gizli'**
  String get hidden;

  /// No description provided for @noCategories.
  ///
  /// In tr, this message translates to:
  /// **'Kategori yok'**
  String get noCategories;

  /// No description provided for @seconds.
  ///
  /// In tr, this message translates to:
  /// **'saniye'**
  String get seconds;

  /// No description provided for @epgSource.
  ///
  /// In tr, this message translates to:
  /// **'EPG Kaynağı'**
  String get epgSource;

  /// No description provided for @addEpgSource.
  ///
  /// In tr, this message translates to:
  /// **'EPG Kaynağı Ekle'**
  String get addEpgSource;

  /// No description provided for @epgUrl.
  ///
  /// In tr, this message translates to:
  /// **'EPG URL (XMLTV)'**
  String get epgUrl;

  /// No description provided for @epgUrlHint.
  ///
  /// In tr, this message translates to:
  /// **'http://example.com/epg.xml'**
  String get epgUrlHint;

  /// No description provided for @xtreamBuiltIn.
  ///
  /// In tr, this message translates to:
  /// **'Xtream Dahili EPG'**
  String get xtreamBuiltIn;

  /// No description provided for @externalEpg.
  ///
  /// In tr, this message translates to:
  /// **'Harici EPG'**
  String get externalEpg;

  /// No description provided for @allChannels.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Kanallar'**
  String get allChannels;

  /// No description provided for @channelCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} kanal'**
  String channelCount(int count);

  /// No description provided for @categoryCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} kategori'**
  String categoryCount(int count);

  /// No description provided for @noChannels.
  ///
  /// In tr, this message translates to:
  /// **'Kanal bulunamadı'**
  String get noChannels;

  /// No description provided for @noMoviesFound.
  ///
  /// In tr, this message translates to:
  /// **'Film bulunamadı'**
  String get noMoviesFound;

  /// No description provided for @noSeriesFound.
  ///
  /// In tr, this message translates to:
  /// **'Dizi bulunamadı'**
  String get noSeriesFound;

  /// No description provided for @seasonCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} Sezon'**
  String seasonCount(int count);

  /// No description provided for @playSeasonEpisode.
  ///
  /// In tr, this message translates to:
  /// **'S{season}E{episode} Oynat'**
  String playSeasonEpisode(String season, String episode);

  /// No description provided for @loading.
  ///
  /// In tr, this message translates to:
  /// **'Yükleniyor...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In tr, this message translates to:
  /// **'Hata'**
  String get error;

  /// No description provided for @retry.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar Dene'**
  String get retry;

  /// No description provided for @save.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get save;

  /// No description provided for @close.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get ok;

  /// No description provided for @back.
  ///
  /// In tr, this message translates to:
  /// **'Geri'**
  String get back;

  /// No description provided for @home.
  ///
  /// In tr, this message translates to:
  /// **'Ana Sayfa'**
  String get home;

  /// No description provided for @continueFrom.
  ///
  /// In tr, this message translates to:
  /// **'Devam Et {time}'**
  String continueFrom(String time);

  /// No description provided for @addedToFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilere eklendi'**
  String get addedToFavorites;

  /// No description provided for @removedFromFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilerden çıkarıldı'**
  String get removedFromFavorites;

  /// No description provided for @myFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilerim'**
  String get myFavorites;

  /// No description provided for @watchHistory.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş'**
  String get watchHistory;

  /// No description provided for @favoriteChannels.
  ///
  /// In tr, this message translates to:
  /// **'Favori Kanallar'**
  String get favoriteChannels;

  /// No description provided for @watchTrailer.
  ///
  /// In tr, this message translates to:
  /// **'Fragman İzle'**
  String get watchTrailer;

  /// No description provided for @newLabel.
  ///
  /// In tr, this message translates to:
  /// **'YENİ'**
  String get newLabel;

  /// No description provided for @noFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Henüz favori eklenmedi'**
  String get noFavorites;

  /// No description provided for @noHistory.
  ///
  /// In tr, this message translates to:
  /// **'Henüz izleme geçmişi yok'**
  String get noHistory;

  /// No description provided for @removeFromHistory.
  ///
  /// In tr, this message translates to:
  /// **'Geçmişten Kaldır'**
  String get removeFromHistory;

  /// No description provided for @clearHistory.
  ///
  /// In tr, this message translates to:
  /// **'Geçmişi Temizle'**
  String get clearHistory;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Tüm izleme geçmişi silinecek. Emin misiniz?'**
  String get clearHistoryConfirm;

  /// No description provided for @removedFromHistory.
  ///
  /// In tr, this message translates to:
  /// **'Geçmişten kaldırıldı'**
  String get removedFromHistory;

  /// No description provided for @historyCleared.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş temizlendi'**
  String get historyCleared;

  /// No description provided for @streamQuality.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Kalitesi'**
  String get streamQuality;

  /// No description provided for @streamQualityDesc.
  ///
  /// In tr, this message translates to:
  /// **'Ağ hızına göre kaliteyi otomatik ayarlar'**
  String get streamQualityDesc;

  /// No description provided for @qualityAuto.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik (Önerilen)'**
  String get qualityAuto;

  /// No description provided for @qualityHigh.
  ///
  /// In tr, this message translates to:
  /// **'Yüksek (1080p)'**
  String get qualityHigh;

  /// No description provided for @qualityMedium.
  ///
  /// In tr, this message translates to:
  /// **'Orta (720p)'**
  String get qualityMedium;

  /// No description provided for @qualityLow.
  ///
  /// In tr, this message translates to:
  /// **'Düşük (480p)'**
  String get qualityLow;

  /// No description provided for @nextProgram.
  ///
  /// In tr, this message translates to:
  /// **'Sıradaki'**
  String get nextProgram;

  /// No description provided for @noEpgInfo.
  ///
  /// In tr, this message translates to:
  /// **'Program bilgisi yok'**
  String get noEpgInfo;

  /// No description provided for @remaining.
  ///
  /// In tr, this message translates to:
  /// **'kalan'**
  String get remaining;

  /// No description provided for @expiration.
  ///
  /// In tr, this message translates to:
  /// **'Son Kullanma'**
  String get expiration;

  /// No description provided for @connections.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantılar'**
  String get connections;

  /// No description provided for @createdAt.
  ///
  /// In tr, this message translates to:
  /// **'Oluşturulma'**
  String get createdAt;

  /// No description provided for @status.
  ///
  /// In tr, this message translates to:
  /// **'Durum'**
  String get status;

  /// No description provided for @accountInfo.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Bilgileri'**
  String get accountInfo;

  /// No description provided for @testConnection.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantıyı Test Et'**
  String get testConnection;

  /// No description provided for @connectionSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı başarılı'**
  String get connectionSuccess;

  /// No description provided for @connectionFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı başarısız'**
  String get connectionFailed;

  /// No description provided for @subtitleSettings.
  ///
  /// In tr, this message translates to:
  /// **'Altyazı Ayarları'**
  String get subtitleSettings;

  /// No description provided for @opensubtitlesApiKey.
  ///
  /// In tr, this message translates to:
  /// **'OpenSubtitles API Anahtarı'**
  String get opensubtitlesApiKey;

  /// No description provided for @opensubtitlesApiKeyDesc.
  ///
  /// In tr, this message translates to:
  /// **'opensubtitles.com adresinden ücretsiz API anahtarı alabilirsiniz'**
  String get opensubtitlesApiKeyDesc;

  /// No description provided for @apiKeyHint.
  ///
  /// In tr, this message translates to:
  /// **'API anahtarınızı girin'**
  String get apiKeyHint;

  /// No description provided for @preferredSubtitleLanguage.
  ///
  /// In tr, this message translates to:
  /// **'Tercih Edilen Altyazı Dili'**
  String get preferredSubtitleLanguage;

  /// No description provided for @preferredSubtitleLanguageDesc.
  ///
  /// In tr, this message translates to:
  /// **'Altyazı ararken öncelikli dil'**
  String get preferredSubtitleLanguageDesc;

  /// No description provided for @subtitleSearchInfo.
  ///
  /// In tr, this message translates to:
  /// **'Film ve dizi oynatırken otomatik altyazı araması yapılır'**
  String get subtitleSearchInfo;

  /// No description provided for @apiKeySaved.
  ///
  /// In tr, this message translates to:
  /// **'API anahtarı kaydedildi'**
  String get apiKeySaved;

  /// No description provided for @apiKeyCleared.
  ///
  /// In tr, this message translates to:
  /// **'API anahtarı temizlendi'**
  String get apiKeyCleared;

  /// No description provided for @subtitleFontSize.
  ///
  /// In tr, this message translates to:
  /// **'Yazı Boyutu'**
  String get subtitleFontSize;

  /// No description provided for @subtitleColor.
  ///
  /// In tr, this message translates to:
  /// **'Yazı Rengi'**
  String get subtitleColor;

  /// No description provided for @subtitleBold.
  ///
  /// In tr, this message translates to:
  /// **'Kalın Yazı'**
  String get subtitleBold;

  /// No description provided for @subtitleBackground.
  ///
  /// In tr, this message translates to:
  /// **'Arka Plan'**
  String get subtitleBackground;

  /// No description provided for @subtitleBackgroundDesc.
  ///
  /// In tr, this message translates to:
  /// **'Altyazının arkasında yarı saydam arka plan'**
  String get subtitleBackgroundDesc;

  /// No description provided for @subtitleAppearance.
  ///
  /// In tr, this message translates to:
  /// **'Altyazı Görünümü'**
  String get subtitleAppearance;

  /// No description provided for @daysRemaining.
  ///
  /// In tr, this message translates to:
  /// **'{count} gün'**
  String daysRemaining(int count);

  /// No description provided for @accountInfoLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Hesap bilgisi yüklenemedi'**
  String get accountInfoLoadFailed;

  /// No description provided for @checking.
  ///
  /// In tr, this message translates to:
  /// **'Kontrol ediliyor...'**
  String get checking;

  /// No description provided for @checkConnection.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantıyı Kontrol Et'**
  String get checkConnection;

  /// No description provided for @visibleCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} görünür'**
  String visibleCount(int count);

  /// No description provided for @hiddenCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} gizli'**
  String hiddenCount(int count);

  /// No description provided for @hiddenLabel.
  ///
  /// In tr, this message translates to:
  /// **'Gizli'**
  String get hiddenLabel;

  /// No description provided for @delete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get delete;

  /// No description provided for @aboutDescription.
  ///
  /// In tr, this message translates to:
  /// **'LifeOS TV, kullanıcıların IPTV servis sağlayıcılarından aldıkları abonelikleri görüntülemelerine olanak tanıyan bir medya oynatıcı uygulamasıdır. Uygulama; canlı TV, film ve dizi içeriklerini destekler.'**
  String get aboutDescription;

  /// No description provided for @developerInfo.
  ///
  /// In tr, this message translates to:
  /// **'Geliştirici Bilgileri'**
  String get developerInfo;

  /// No description provided for @developer.
  ///
  /// In tr, this message translates to:
  /// **'Geliştirici'**
  String get developer;

  /// No description provided for @website.
  ///
  /// In tr, this message translates to:
  /// **'Web Sitesi'**
  String get website;

  /// No description provided for @license.
  ///
  /// In tr, this message translates to:
  /// **'Lisans'**
  String get license;

  /// No description provided for @allRightsReserved.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Hakları Saklıdır (All Rights Reserved)'**
  String get allRightsReserved;

  /// No description provided for @copyrightNotice.
  ///
  /// In tr, this message translates to:
  /// **'Copyright (c) 2026 Erkan ÖZ'**
  String get copyrightNotice;

  /// No description provided for @legalDisclaimer.
  ///
  /// In tr, this message translates to:
  /// **'Yasal Uyarı'**
  String get legalDisclaimer;

  /// No description provided for @disclaimerText.
  ///
  /// In tr, this message translates to:
  /// **'LifeOS TV yalnızca bir medya oynatıcı uygulamasıdır. Uygulama herhangi bir içerik barındırmaz, dağıtmaz veya sağlamaz. Kullanıcılar, eriştikleri içeriklerden ve kullandıkları IPTV hizmetlerinin yasallığından tamamen kendileri sorumludur. Uygulama geliştiricisi, kullanıcıların üçüncü taraf hizmetler aracılığıyla eriştikleri içeriklerle ilgili hiçbir sorumluluk kabul etmez. Telif hakkı ihlali dahil olmak üzere, yasadışı içeriklere erişim konusundaki tüm yasal sorumluluk kullanıcıya aittir.'**
  String get disclaimerText;

  /// No description provided for @licenseText.
  ///
  /// In tr, this message translates to:
  /// **'Bu yazılımın kaynak kodları, tasarımı ve algoritmaları Erkan ÖZ\'e aittir. Yazılımın izinsiz kopyalanması, çoğaltılması, değiştirilmesi, dağıtılması veya tersine mühendislik (reverse engineering) işlemlerine tabi tutulması kesinlikle yasaktır. Bu yazılım önceden yazılı izin alınmaksızın ticari veya ticari olmayan amaçlarla kullanılamaz. Açıkça belirtilmedikçe hiçbir kullanım hakkı devredilemez veya alt lisanslanamaz.'**
  String get licenseText;

  /// No description provided for @exitConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamadan çıkmak için tekrar basın'**
  String get exitConfirm;

  /// No description provided for @noProgramInfo.
  ///
  /// In tr, this message translates to:
  /// **'Yayın akışı bilgisi bulunamadı'**
  String get noProgramInfo;

  /// No description provided for @backupNow.
  ///
  /// In tr, this message translates to:
  /// **'Yedek Al'**
  String get backupNow;

  /// No description provided for @backupNowDesc.
  ///
  /// In tr, this message translates to:
  /// **'Hesaplar, favoriler, izleme geçmişi ve ayarları JSON olarak dışa aktar'**
  String get backupNowDesc;

  /// No description provided for @restoreFromBackup.
  ///
  /// In tr, this message translates to:
  /// **'Yedeği Yükle'**
  String get restoreFromBackup;

  /// No description provided for @restoreFromBackupDesc.
  ///
  /// In tr, this message translates to:
  /// **'Önceki yedek dosyasından içe aktar'**
  String get restoreFromBackupDesc;

  /// No description provided for @backupSaved.
  ///
  /// In tr, this message translates to:
  /// **'Yedek kaydedildi'**
  String get backupSaved;

  /// No description provided for @backupRestored.
  ///
  /// In tr, this message translates to:
  /// **'Yedek başarıyla yüklendi'**
  String get backupRestored;

  /// No description provided for @backupFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yedekleme başarısız'**
  String get backupFailed;

  /// No description provided for @backupInvalidFormat.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz yedek dosyası'**
  String get backupInvalidFormat;

  /// No description provided for @restoreConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut hesaplar, favoriler ve geçmiş yedek içeriğiyle değiştirilecek. Devam edilsin mi?'**
  String get restoreConfirm;

  /// No description provided for @similarContent.
  ///
  /// In tr, this message translates to:
  /// **'Benzer İçerikler'**
  String get similarContent;

  /// No description provided for @similarSeries.
  ///
  /// In tr, this message translates to:
  /// **'Benzer Diziler'**
  String get similarSeries;

  /// No description provided for @resetContentData.
  ///
  /// In tr, this message translates to:
  /// **'İzleme verilerini sıfırla'**
  String get resetContentData;

  /// No description provided for @resetContentDataDesc.
  ///
  /// In tr, this message translates to:
  /// **'Kanallar, kategoriler ve EPG tablolarını temizler. Favoriler ve hesap bilgileri korunur.'**
  String get resetContentDataDesc;

  /// No description provided for @resetContentDataConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Kanallar, kategoriler ve EPG silinecek. Hesap bilgilerin ve favorilerin korunur. Bir sonraki açılışta yeniden senkronize edilir.'**
  String get resetContentDataConfirm;

  /// No description provided for @resetContentDataDone.
  ///
  /// In tr, this message translates to:
  /// **'İçerik verileri sıfırlandı'**
  String get resetContentDataDone;

  /// No description provided for @reset.
  ///
  /// In tr, this message translates to:
  /// **'Sıfırla'**
  String get reset;

  /// No description provided for @sleepTimer.
  ///
  /// In tr, this message translates to:
  /// **'Uyku Zamanlayıcısı'**
  String get sleepTimer;

  /// No description provided for @sleepTimerStopAtEpisodeEnd.
  ///
  /// In tr, this message translates to:
  /// **'Bölüm bitiminde durdur'**
  String get sleepTimerStopAtEpisodeEnd;

  /// No description provided for @sleepTimerCancelAction.
  ///
  /// In tr, this message translates to:
  /// **'İptal Et'**
  String get sleepTimerCancelAction;

  /// No description provided for @sleepTimerFired.
  ///
  /// In tr, this message translates to:
  /// **'Uyku zamanlayıcısı: oynatma duraklatıldı'**
  String get sleepTimerFired;

  /// No description provided for @minutesShort.
  ///
  /// In tr, this message translates to:
  /// **'{minutes} dk'**
  String minutesShort(int minutes);

  /// No description provided for @watchlist.
  ///
  /// In tr, this message translates to:
  /// **'Listem'**
  String get watchlist;

  /// No description provided for @addToWatchlist.
  ///
  /// In tr, this message translates to:
  /// **'Listeme Ekle'**
  String get addToWatchlist;

  /// No description provided for @removeFromWatchlist.
  ///
  /// In tr, this message translates to:
  /// **'Listemden Çıkar'**
  String get removeFromWatchlist;

  /// No description provided for @addedToWatchlist.
  ///
  /// In tr, this message translates to:
  /// **'Listeme eklendi'**
  String get addedToWatchlist;

  /// No description provided for @removedFromWatchlist.
  ///
  /// In tr, this message translates to:
  /// **'Listemden çıkarıldı'**
  String get removedFromWatchlist;

  /// No description provided for @streamStats.
  ///
  /// In tr, this message translates to:
  /// **'Akış Bilgileri'**
  String get streamStats;

  /// No description provided for @resolution.
  ///
  /// In tr, this message translates to:
  /// **'Çözünürlük'**
  String get resolution;

  /// No description provided for @videoCodec.
  ///
  /// In tr, this message translates to:
  /// **'Video Codec'**
  String get videoCodec;

  /// No description provided for @audioCodec.
  ///
  /// In tr, this message translates to:
  /// **'Ses Codec'**
  String get audioCodec;

  /// No description provided for @bitrate.
  ///
  /// In tr, this message translates to:
  /// **'Bit Hızı'**
  String get bitrate;

  /// No description provided for @frameRate.
  ///
  /// In tr, this message translates to:
  /// **'Kare Hızı'**
  String get frameRate;

  /// No description provided for @audioChannels.
  ///
  /// In tr, this message translates to:
  /// **'Ses Kanalları'**
  String get audioChannels;

  /// No description provided for @droppedFrames.
  ///
  /// In tr, this message translates to:
  /// **'Düşen Kareler'**
  String get droppedFrames;

  /// No description provided for @sortBy.
  ///
  /// In tr, this message translates to:
  /// **'Sırala'**
  String get sortBy;

  /// No description provided for @sortByRecent.
  ///
  /// In tr, this message translates to:
  /// **'En Yeni'**
  String get sortByRecent;

  /// No description provided for @sortByRating.
  ///
  /// In tr, this message translates to:
  /// **'Puana Göre'**
  String get sortByRating;

  /// No description provided for @sortByName.
  ///
  /// In tr, this message translates to:
  /// **'Ada Göre'**
  String get sortByName;

  /// No description provided for @castDevices.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Cihazları'**
  String get castDevices;

  /// No description provided for @castDisconnect.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantıyı Kes'**
  String get castDisconnect;

  /// No description provided for @castSearching.
  ///
  /// In tr, this message translates to:
  /// **'Cihazlar aranıyor…'**
  String get castSearching;

  /// No description provided for @castNoDevices.
  ///
  /// In tr, this message translates to:
  /// **'Chromecast cihazı bulunamadı'**
  String get castNoDevices;

  /// No description provided for @castSearchAgain.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar Ara'**
  String get castSearchAgain;

  /// No description provided for @channelList.
  ///
  /// In tr, this message translates to:
  /// **'Kanal Listesi'**
  String get channelList;

  /// No description provided for @searchChannelsHint.
  ///
  /// In tr, this message translates to:
  /// **'Kanal ara...'**
  String get searchChannelsHint;

  /// No description provided for @all.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get all;

  /// No description provided for @subtitlePosition.
  ///
  /// In tr, this message translates to:
  /// **'Altyazı konumu'**
  String get subtitlePosition;

  /// No description provided for @skipIntroLabel.
  ///
  /// In tr, this message translates to:
  /// **'Intro\'yu Atla'**
  String get skipIntroLabel;

  /// No description provided for @accountSaveFailed.
  ///
  /// In tr, this message translates to:
  /// **'Hesap kaydedilemedi'**
  String get accountSaveFailed;

  /// No description provided for @connecting.
  ///
  /// In tr, this message translates to:
  /// **'Bağlanıyor...'**
  String get connecting;

  /// No description provided for @loadingPlaylistData.
  ///
  /// In tr, this message translates to:
  /// **'Liste verileri yükleniyor...'**
  String get loadingPlaylistData;

  /// No description provided for @pleaseWaitDoNotClose.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bekleyin, uygulamayı kapatmayın'**
  String get pleaseWaitDoNotClose;

  /// No description provided for @pleaseEnterUrl.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen URL girin'**
  String get pleaseEnterUrl;

  /// No description provided for @pleaseEnterUsername.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen kullanıcı adı girin'**
  String get pleaseEnterUsername;

  /// No description provided for @pleaseEnterPassword.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen şifre girin'**
  String get pleaseEnterPassword;

  /// No description provided for @pleaseEnterAUrl.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir URL girin'**
  String get pleaseEnterAUrl;

  /// No description provided for @xtreamM3uAutoDetectInfo.
  ///
  /// In tr, this message translates to:
  /// **'Xtream M3U bağlantıları (kullanıcı adı ve şifre içeren) otomatik algılanır.'**
  String get xtreamM3uAutoDetectInfo;

  /// No description provided for @searchVodHint.
  ///
  /// In tr, this message translates to:
  /// **'Film veya dizi adı...'**
  String get searchVodHint;

  /// No description provided for @subtitleNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Altyazı bulunamadı'**
  String get subtitleNotFound;

  /// No description provided for @trialBadge.
  ///
  /// In tr, this message translates to:
  /// **'Deneme'**
  String get trialBadge;

  /// No description provided for @skipIntro.
  ///
  /// In tr, this message translates to:
  /// **'İntroyu Atla'**
  String get skipIntro;

  /// No description provided for @skipIntroSetting.
  ///
  /// In tr, this message translates to:
  /// **'İntro Atla butonu göster'**
  String get skipIntroSetting;

  /// No description provided for @skipIntroSettingDesc.
  ///
  /// In tr, this message translates to:
  /// **'Açık olduğunda, oynatıcı işaretlenmiş intro aralığındayken \'İntroyu Atla\' butonu gösterir.'**
  String get skipIntroSettingDesc;

  /// No description provided for @markIntroStart.
  ///
  /// In tr, this message translates to:
  /// **'İntro burada başlıyor'**
  String get markIntroStart;

  /// No description provided for @markIntroEnd.
  ///
  /// In tr, this message translates to:
  /// **'İntro burada bitiyor'**
  String get markIntroEnd;

  /// No description provided for @introMarked.
  ///
  /// In tr, this message translates to:
  /// **'İntro kaydedildi. Sonraki bölümde atlamayı önerecek.'**
  String get introMarked;

  /// No description provided for @introCleared.
  ///
  /// In tr, this message translates to:
  /// **'İntro işareti silindi.'**
  String get introCleared;

  /// No description provided for @introMarkInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş zamanı başlangıçtan sonra olmalı.'**
  String get introMarkInvalid;

  /// No description provided for @showTrailerSetting.
  ///
  /// In tr, this message translates to:
  /// **'Fragman göster'**
  String get showTrailerSetting;

  /// No description provided for @showTrailerSettingDesc.
  ///
  /// In tr, this message translates to:
  /// **'Detay sayfasının sağ üstündeki küçük YouTube fragmanı. Statik bir panel istiyorsan kapat.'**
  String get showTrailerSettingDesc;

  /// No description provided for @aiAssistant.
  ///
  /// In tr, this message translates to:
  /// **'AI Asistan'**
  String get aiAssistant;

  /// No description provided for @aiAssistantSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Opsiyonel — ücretsiz Google Gemini API key\'i yapıştırarak akıllı özellikleri aç.'**
  String get aiAssistantSubtitle;

  /// No description provided for @aiAssistantWhy.
  ///
  /// In tr, this message translates to:
  /// **'Key girince neler kazanırsın'**
  String get aiAssistantWhy;

  /// No description provided for @aiBenefitNaturalSearch.
  ///
  /// In tr, this message translates to:
  /// **'Doğal dil arama (\"kısa süreli Kore polisiye dizisi\")'**
  String get aiBenefitNaturalSearch;

  /// No description provided for @aiBenefitTonightChat.
  ///
  /// In tr, this message translates to:
  /// **'\"Bu akşam ne izlesem?\" sohbet asistanı'**
  String get aiBenefitTonightChat;

  /// No description provided for @aiBenefitRecap.
  ///
  /// In tr, this message translates to:
  /// **'Bıraktığın yerin spoiler içermeyen özeti'**
  String get aiBenefitRecap;

  /// No description provided for @aiBenefitPlot.
  ///
  /// In tr, this message translates to:
  /// **'Konu özeti, çeviri ve zenginleştirme'**
  String get aiBenefitPlot;

  /// No description provided for @aiBenefitSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Altyazı yoksa akıllı çeviri'**
  String get aiBenefitSubtitle;

  /// No description provided for @aiPrivacyNote.
  ///
  /// In tr, this message translates to:
  /// **'Arama sorguları Google\'a gönderilir. Key cihazında tutulur, istediğin zaman silebilirsin.'**
  String get aiPrivacyNote;

  /// No description provided for @geminiApiKey.
  ///
  /// In tr, this message translates to:
  /// **'Gemini API anahtarı'**
  String get geminiApiKey;

  /// No description provided for @geminiApiKeyHint.
  ///
  /// In tr, this message translates to:
  /// **'AIzaSy…'**
  String get geminiApiKeyHint;

  /// No description provided for @geminiSaveKey.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get geminiSaveKey;

  /// No description provided for @geminiClearKey.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get geminiClearKey;

  /// No description provided for @geminiTestKey.
  ///
  /// In tr, this message translates to:
  /// **'Test et'**
  String get geminiTestKey;

  /// No description provided for @geminiKeySaved.
  ///
  /// In tr, this message translates to:
  /// **'Key kaydedildi. AI özellikleri aktif.'**
  String get geminiKeySaved;

  /// No description provided for @geminiKeyCleared.
  ///
  /// In tr, this message translates to:
  /// **'Key silindi. AI özellikleri gizlendi.'**
  String get geminiKeyCleared;

  /// No description provided for @geminiKeyInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Key boş veya geçersiz.'**
  String get geminiKeyInvalid;

  /// No description provided for @geminiKeyTestSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Key çalışıyor! Gemini\'den yanıt geldi.'**
  String get geminiKeyTestSuccess;

  /// No description provided for @geminiKeyTestFailed.
  ///
  /// In tr, this message translates to:
  /// **'Test başarısız: {reason}'**
  String geminiKeyTestFailed(String reason);

  /// No description provided for @geminiStatusActive.
  ///
  /// In tr, this message translates to:
  /// **'Aktif'**
  String get geminiStatusActive;

  /// No description provided for @geminiStatusInactive.
  ///
  /// In tr, this message translates to:
  /// **'Yapılandırılmadı'**
  String get geminiStatusInactive;

  /// No description provided for @howToGetGeminiKey.
  ///
  /// In tr, this message translates to:
  /// **'Key\'i nasıl alırım?'**
  String get howToGetGeminiKey;

  /// No description provided for @geminiStep1.
  ///
  /// In tr, this message translates to:
  /// **'1. Tarayıcıda aistudio.google.com adresine git'**
  String get geminiStep1;

  /// No description provided for @geminiStep2.
  ///
  /// In tr, this message translates to:
  /// **'2. Herhangi bir Google hesabıyla giriş yap'**
  String get geminiStep2;

  /// No description provided for @geminiStep3.
  ///
  /// In tr, this message translates to:
  /// **'3. \"Get API key\" → \"Create new\" tıkla'**
  String get geminiStep3;

  /// No description provided for @geminiStep4.
  ///
  /// In tr, this message translates to:
  /// **'4. Key\'i kopyala (AIzaSy… ile başlar)'**
  String get geminiStep4;

  /// No description provided for @geminiStep5.
  ///
  /// In tr, this message translates to:
  /// **'5. Yukarıdaki alana yapıştır ve Kaydet\'e bas'**
  String get geminiStep5;

  /// No description provided for @geminiFreeReassurance.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz, kart gerekmez. Kişisel kullanım için günlük kota fazlasıyla yeterli.'**
  String get geminiFreeReassurance;

  /// No description provided for @openGeminiSite.
  ///
  /// In tr, this message translates to:
  /// **'aistudio.google.com\'u aç'**
  String get openGeminiSite;

  /// No description provided for @aiChatTitle.
  ///
  /// In tr, this message translates to:
  /// **'AI Asistan'**
  String get aiChatTitle;

  /// No description provided for @aiChatGreeting.
  ///
  /// In tr, this message translates to:
  /// **'Selam! Ne izlemek istediğini söyle ya da bir film/dizi hakkında bilgi iste — kütüphanene göre cevap vereyim.'**
  String get aiChatGreeting;

  /// No description provided for @aiChatInputHint.
  ///
  /// In tr, this message translates to:
  /// **'Asistana sor…'**
  String get aiChatInputHint;

  /// No description provided for @aiThinking.
  ///
  /// In tr, this message translates to:
  /// **'Düşünüyor…'**
  String get aiThinking;

  /// No description provided for @aiSend.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get aiSend;

  /// No description provided for @aiNoMatches.
  ///
  /// In tr, this message translates to:
  /// **'Kütüphanende buna uyan bir şey bulamadım. Biraz farklı sor?'**
  String get aiNoMatches;

  /// No description provided for @aiError.
  ///
  /// In tr, this message translates to:
  /// **'Asistana ulaşılamadı. Birazdan tekrar dene.'**
  String get aiError;

  /// No description provided for @aiEmptyLibrary.
  ///
  /// In tr, this message translates to:
  /// **'Kütüphanen boş. Önce içeriği senkronize et.'**
  String get aiEmptyLibrary;

  /// No description provided for @aiSuggestTonight.
  ///
  /// In tr, this message translates to:
  /// **'Bu akşam ne izleyim?'**
  String get aiSuggestTonight;

  /// No description provided for @aiSuggestTogether.
  ///
  /// In tr, this message translates to:
  /// **'Eşimle izleyebileceğim bir şey'**
  String get aiSuggestTogether;

  /// No description provided for @aiSuggestShort.
  ///
  /// In tr, this message translates to:
  /// **'90 dakikadan kısa'**
  String get aiSuggestShort;

  /// No description provided for @aiSuggestKids.
  ///
  /// In tr, this message translates to:
  /// **'Çocuklar için bir şey'**
  String get aiSuggestKids;

  /// No description provided for @aiSuggestAboutTitle.
  ///
  /// In tr, this message translates to:
  /// **'Phantom Lawyer hakkında bilgi ver'**
  String get aiSuggestAboutTitle;

  /// No description provided for @aiWhyThis.
  ///
  /// In tr, this message translates to:
  /// **'Neden bu?'**
  String get aiWhyThis;

  /// No description provided for @aiPlay.
  ///
  /// In tr, this message translates to:
  /// **'Oynat'**
  String get aiPlay;

  /// No description provided for @aiOpenDetails.
  ///
  /// In tr, this message translates to:
  /// **'Detay'**
  String get aiOpenDetails;

  /// No description provided for @aiPlotTranslate.
  ///
  /// In tr, this message translates to:
  /// **'Türkçe\'ye çevir'**
  String get aiPlotTranslate;

  /// No description provided for @aiPlotSummarize.
  ///
  /// In tr, this message translates to:
  /// **'Spoiler-free özet'**
  String get aiPlotSummarize;

  /// No description provided for @aiPlotFillIn.
  ///
  /// In tr, this message translates to:
  /// **'Plot bilgisi getir'**
  String get aiPlotFillIn;

  /// No description provided for @aiPlotDetailedInfo.
  ///
  /// In tr, this message translates to:
  /// **'Detaylı bilgi'**
  String get aiPlotDetailedInfo;

  /// No description provided for @aiPlotEnriching.
  ///
  /// In tr, this message translates to:
  /// **'Hazırlıyor…'**
  String get aiPlotEnriching;

  /// No description provided for @aiPlotError.
  ///
  /// In tr, this message translates to:
  /// **'Alınamadı — tekrar dene'**
  String get aiPlotError;

  /// No description provided for @aiPlotShowOriginal.
  ///
  /// In tr, this message translates to:
  /// **'Orijinali göster'**
  String get aiPlotShowOriginal;

  /// No description provided for @aiPlotEnrichedTag.
  ///
  /// In tr, this message translates to:
  /// **'AI'**
  String get aiPlotEnrichedTag;

  /// No description provided for @aiRecapPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Şimdiye kadar olanı hatırlat'**
  String get aiRecapPrompt;

  /// No description provided for @aiRecapHide.
  ///
  /// In tr, this message translates to:
  /// **'Özeti gizle'**
  String get aiRecapHide;

  /// No description provided for @aiRecapTag.
  ///
  /// In tr, this message translates to:
  /// **'Özet'**
  String get aiRecapTag;

  /// No description provided for @aiSimilarTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sana özel benzer içerikler'**
  String get aiSimilarTitle;

  /// No description provided for @aiSimilarLoading.
  ///
  /// In tr, this message translates to:
  /// **'Hazırlanıyor…'**
  String get aiSimilarLoading;

  /// No description provided for @aiSimilarFailed.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı öneriler yüklenemedi — basit liste gösteriliyor.'**
  String get aiSimilarFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'de',
    'en',
    'es',
    'fr',
    'ku',
    'ru',
    'tr',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ku':
      return AppLocalizationsKu();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
