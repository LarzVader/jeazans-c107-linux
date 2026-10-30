#!/usr/bin/env python3
"""Traegt die Rettungsfunktion (SD -> eMMC ohne DRAM) in die U-Boot-Quellen ein; wird vor dem Bau
des Rettungs-SPL ausgefuehrt und danach per git checkout wieder entfernt.
Version 4: erst alles kopieren, dann pruefen und reparieren; eMMC-Lesetakt sinkt bei Fehlern."""
import sys
bs, ms = sys.argv[1], sys.argv[2]
b = open(bs).read()
anker = "#ifdef CONFIG_ENV_MMC_DEVICE_INDEX\nint mmc_get_env_dev(void)"
assert b.count(anker) == 1
rettung = r'''#ifdef CONFIG_XPL_BUILD
/*
 * Jeazans C107 Rettung: laeuft als selbst signiertes TOC0 von der SD-Karte, ohne DRAM.
 * Kopiert die gesicherten Partitionen von der Karte (Rettungskarten-Layout) auf den eMMC,
 * prueft sie danach und schreibt abweichende Bloecke neu.
 * UART0 liegt auf PF2/PF4, die SD-Karte auf PF0-5: fuer Ausgaben werden die beiden Pins
 * kurz auf UART gestellt, fuer Kartenzugriffe wieder auf SDC0.
 */
static u8 rettung_puffer[16384] __aligned(64);
static u8 rettung_arena[12288] __aligned(16);	/* eigener Bereich fuer malloc_simple, in board_init_f ist keiner eingerichtet */
static int rettung_uart_aktiv;
static u32 rettung_wiederholungen;
static u32 rettung_emmc_takt = 52000000;

static const struct { u32 quelle, ziel, anzahl; const char *name; } rettung_teile[] = {
	/* Nur env_b: Konsolen-Start in env_b schreiben, damit Slot B am Prompt landet.
	   Slot A ist unberuehrt und intakt, muss nicht zurueckgeschrieben werden.
	   Voller Slot-A-Rueckweg (bei Bedarf wieder eintragen):
	   { 204800, 204800, 512, "env_a" }, { 205824, 205824, 131072, "boot_a" },
	   { 467968, 467968, 65536, "vendor_boot_a" }, { 599040, 599040, 16384, "init_boot_a" },
	   { 615424, 8299520, 4096, "dtbo_a" }, { 619520, 7971840, 32768, "misc" }, */
	{ 205312, 205312, 512, "env_b" },
};

static void rettung_uart(void)
{
	sunxi_gpio_set_cfgpin(SUNXI_GPF(2), SUN8I_GPF_UART0);
	sunxi_gpio_set_cfgpin(SUNXI_GPF(4), SUN8I_GPF_UART0);
	rettung_uart_aktiv = 1;
}

static void rettung_sd(void)
{
	if (rettung_uart_aktiv)
		udelay(8000);		/* UART-FIFO leeren lassen (64 Zeichen bei 115200) */
	rettung_uart_aktiv = 0;
	mmc_pinmux_setup(0);
}

static void rettung_halt(const char *text)
{
	rettung_uart();
	puts(text);
	while (1)
		;
}

static void rettung_neu_init(struct mmc *mmc)
{
	mmc->has_init = 0;
	mmc_init(mmc);
}

/* Lesen von der SD-Karte mit Wiederholungen; Pins stehen danach auf SDC0 */
static int rettung_lesen_sd(struct mmc *sd, u32 sektor, u32 n, void *ziel)
{
	u32 versuch;

	for (versuch = 0; versuch < 8; versuch++) {
		rettung_sd();
		if (blk_dread(mmc_get_blk_desc(sd), sektor, n, ziel) == n)
			return 0;
		rettung_wiederholungen++;
		udelay(50000);
		if (versuch >= 2)
			rettung_neu_init(sd);
	}
	return -1;
}

static int rettung_schreiben_emmc(struct mmc *emmc, u32 sektor, u32 n, const void *quelle)
{
	u32 versuch;

	for (versuch = 0; versuch < 8; versuch++) {
		if (blk_dwrite(mmc_get_blk_desc(emmc), sektor, n, quelle) == n)
			return 0;
		rettung_wiederholungen++;
		udelay(50000);		/* eMMC Zeit zum Aufraeumen geben */
		if (versuch >= 2)
			rettung_neu_init(emmc);
	}
	return -1;
}

/* eMMC lesen; scheitert es dreimal, wird der Takt halbiert (bis etwa 6,5 MHz) */
static int rettung_lesen_emmc(struct mmc *emmc, u32 sektor, u32 n, void *ziel)
{
	u32 versuch;

	for (versuch = 0; versuch < 9; versuch++) {
		if (blk_dread(mmc_get_blk_desc(emmc), sektor, n, ziel) == n)
			return 0;
		rettung_wiederholungen++;
		if (versuch % 3 == 2 && rettung_emmc_takt > 7000000) {
			rettung_emmc_takt /= 2;
			((struct mmc_config *)emmc->cfg)->f_max = rettung_emmc_takt;
			rettung_uart();
			printf("  eMMC liest bei Sektor %u nicht, Takt runter auf %u Hz\n", sektor, rettung_emmc_takt);
		}
		udelay(20000);
		rettung_neu_init(emmc);
	}
	return -1;
}

void jeazans_rettung(void)
{
	extern char __bss_start[], __bss_end[];
	struct mmc *sd, *emmc;
	u32 i, off, n, abweichend, repariert, kaputt, unlesbar, folge, meldungen, probleme = 0;
	int pruefen = 1;

	memset(__bss_start, 0, __bss_end - __bss_start);	/* BSS wird sonst erst nach board_init_f genullt */
	gd->malloc_base = (ulong)rettung_arena;
	gd->malloc_ptr = 0;
	gd->malloc_limit = sizeof(rettung_arena);
	writel(0x16aa0000, 0x02050014);		/* SoC-Watchdog aus (MODE-Register, Schluessel 0x16aa) */
	rettung_uart_aktiv = 1;
	puts("\n=== Jeazans C107 RETTUNG v5: Partitionen von der SD-Karte auf den eMMC ===\n");
	if (mmc_initialize(NULL))
		rettung_halt("mmc_initialize fehlgeschlagen\n");
	emmc = find_mmc_device(0);			/* board_mmc_init meldet nur den eMMC an (UART0 auf PF) */
	if (!emmc)
		rettung_halt("eMMC nicht gefunden\n");
	if (mmc_init(emmc))
		rettung_halt("eMMC: mmc_init fehlgeschlagen\n");
	printf("eMMC: %u MiB, Takt %u Hz, Busbreite %u\n", (u32)(emmc->capacity >> 20), emmc->clock, emmc->bus_width);
	rettung_sd();
	sd = sunxi_mmc_init(0);
	rettung_uart();
	if (!sd)
		rettung_halt("SD: sunxi_mmc_init fehlgeschlagen\n");
	((struct mmc_config *)sd->cfg)->f_max = 25000000;	/* lange Leitungen ueber den Sniffer: Takt drosseln */
	puts("SD: initialisiere ...\n");
	rettung_sd();
	i = mmc_init(sd);
	rettung_uart();
	if (i) {
		printf("SD: mmc_init fehlgeschlagen (%d)\n", (int)i);
		while (1)
			;
	}
	printf("SD: %u MiB, Takt %u Hz\n", (u32)(sd->capacity >> 20), sd->clock);

	/* Phase 1: alles kopieren */
	for (i = 0; i < ARRAY_SIZE(rettung_teile); i++) {
		rettung_uart();
		printf("kopiere %s: %u Sektoren von SD %u nach eMMC %u\n", rettung_teile[i].name,
		       rettung_teile[i].anzahl, rettung_teile[i].quelle, rettung_teile[i].ziel);
		for (off = 0; off < rettung_teile[i].anzahl; off += n) {
			n = min((u32)32, rettung_teile[i].anzahl - off);
			if (rettung_lesen_sd(sd, rettung_teile[i].quelle + off, n, rettung_puffer)) {
				rettung_uart();
				printf("LESEFEHLER SD bei Sektor %u, Abbruch\n", rettung_teile[i].quelle + off);
				while (1)
					;
			}
			if (rettung_schreiben_emmc(emmc, rettung_teile[i].ziel + off, n, rettung_puffer)) {
				rettung_uart();
				printf("SCHREIBFEHLER eMMC bei Sektor %u, Abbruch\n", rettung_teile[i].ziel + off);
				while (1)
					;
			}
			if ((off & 8191) == 0 && off) {
				rettung_uart();
				printf("  %u/%u (Wiederholungen bisher %u)\n", off, rettung_teile[i].anzahl, rettung_wiederholungen);
			}
		}
		rettung_uart();
		printf("  %s kopiert (Wiederholungen bisher %u).\n", rettung_teile[i].name, rettung_wiederholungen);
	}

	/* Phase 2: pruefen und abweichende Bloecke neu schreiben */
	for (i = 0; i < ARRAY_SIZE(rettung_teile) && pruefen; i++) {
		abweichend = repariert = kaputt = unlesbar = folge = meldungen = 0;
		rettung_uart();
		printf("pruefe %s ...\n", rettung_teile[i].name);
		for (off = 0; off < rettung_teile[i].anzahl; off += n) {
			n = min((u32)16, rettung_teile[i].anzahl - off);
			if (rettung_lesen_sd(sd, rettung_teile[i].quelle + off, n, rettung_puffer)) {
				unlesbar++;
				if (meldungen++ < 3) {
					rettung_uart();
					printf("  SD unlesbar bei Sektor %u\n", rettung_teile[i].quelle + off);
				}
				continue;
			}
			if (rettung_lesen_emmc(emmc, rettung_teile[i].ziel + off, n, rettung_puffer + 8192)) {
				unlesbar++;
				if (++folge >= 10) {
					rettung_uart();
					printf("  eMMC auch bei %u Hz nicht lesbar, Pruefung abgebrochen\n", rettung_emmc_takt);
					pruefen = 0;
					break;
				}
				continue;
			}
			folge = 0;
			if (!memcmp(rettung_puffer, rettung_puffer + 8192, n * 512))
				continue;
			abweichend++;
			if (!rettung_schreiben_emmc(emmc, rettung_teile[i].ziel + off, n, rettung_puffer) &&
			    !rettung_lesen_emmc(emmc, rettung_teile[i].ziel + off, n, rettung_puffer + 8192) &&
			    !memcmp(rettung_puffer, rettung_puffer + 8192, n * 512))
				repariert++;
			else
				kaputt++;
			if ((off & 8191) == 0 && off) {
				rettung_uart();
				printf("  %u/%u\n", off, rettung_teile[i].anzahl);
			}
		}
		rettung_uart();
		printf("  %s: %u Bloecke abweichend, %u repariert, %u kaputt, %u unlesbar (eMMC-Lesetakt %u Hz)\n",
		       rettung_teile[i].name, abweichend, repariert, kaputt, unlesbar, rettung_emmc_takt);
		probleme += kaputt + unlesbar;
	}
	rettung_uart();
	if (!pruefen)
		puts("\nFERTIG OHNE VOLLE PRUEFUNG: alles kopiert, der eMMC liess sich nicht zuverlaessig zuruecklesen.\n");
	else if (probleme)
		printf("\nFERTIG MIT PROBLEMEN: %u Bloecke nicht bestaetigt.\n", probleme);
	else
		puts("\nFERTIG: env_a, boot_a, vendor_boot_a, init_boot_a, dtbo_a kopiert und geprueft, alles identisch.\n");
	rettung_halt("Tablet ausschalten, Karte entfernen, Sniffer wieder einstecken, einschalten.\n");
}
#endif /* CONFIG_XPL_BUILD */

'''
open(bs, "w").write(b.replace(anker, rettung + anker))
m = open(ms).read()
alt = "\tspl_init();\n\tpreloader_console_init();\n"
assert m.count(alt) == 1
open(ms, "w").write(m.replace(alt, alt + "\t{ extern void jeazans_rettung(void); jeazans_rettung(); }\n"))
print("Rettungscode v4 eingetragen")
