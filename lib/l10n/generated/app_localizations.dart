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
  /// **'ör. IPTV\'im'**
  String get accountNameHint;

  /// No description provided for @playlistName.
  ///
  /// In tr, this message translates to:
  /// **'Playlist Adı'**
  String get playlistName;

  /// No description provided for @playlistNameHint.
  ///
  /// In tr, this message translates to:
  /// **'ör. Playlist\'im'**
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
